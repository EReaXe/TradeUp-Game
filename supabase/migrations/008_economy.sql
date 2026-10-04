-- Phase 8. Apply after 007 and seed. Online global economy; no offline catch-up.
begin;
create table if not exists public.economy_clock (
 id boolean primary key default true check(id),
 last_tick_at timestamptz not null default now(),
 tick bigint not null default 0 check(tick>=0)
);
insert into public.economy_clock(id) values(true) on conflict do nothing;
create table if not exists public.product_economy (
 product_id uuid primary key references public.products(id),
 reference_market_kurus bigint not null check(reference_market_kurus between 1 and 1000000000000),
 reference_wholesale_kurus bigint not null check(reference_wholesale_kurus between 1 and 1000000000000),
 reference_demand integer not null check(reference_demand between 0 and 100),
 reference_supply integer not null check(reference_supply between 0 and 100),
 target_stock integer not null check(target_stock between 1 and 1000000)
);
insert into public.product_economy
 select id,market_price_kurus,wholesale_price_kurus,demand,supply,
 case rarity when 'Common' then 2500 when 'Uncommon' then 800 when 'Rare' then 200 when 'Epic' then 40 else 10 end
 from public.products on conflict do nothing;
create table if not exists public.price_history (
 product_id uuid not null references public.products(id),
 tick bigint not null check(tick>=0),
 recorded_at timestamptz not null default now(),
 market_price_kurus bigint not null check(market_price_kurus between 1 and 1000000000000),
 wholesale_price_kurus bigint not null check(wholesale_price_kurus between 1 and 1000000000000),
 demand integer not null check(demand between 0 and 100),
 supply integer not null check(supply between 0 and 100),
 system_stock integer not null check(system_stock between 0 and 1000000),
 primary key(product_id,tick)
);
create index if not exists price_history_product_time on public.price_history(product_id,recorded_at desc);
insert into public.price_history(product_id,tick,market_price_kurus,wholesale_price_kurus,demand,supply,system_stock)
 select p.id,c.tick,p.market_price_kurus,p.wholesale_price_kurus,p.demand,p.supply,p.system_stock
 from public.products p cross join public.economy_clock c on conflict do nothing;
alter table public.economy_clock enable row level security;
alter table public.product_economy enable row level security;
alter table public.price_history enable row level security;
revoke all on public.economy_clock,public.product_economy,public.price_history from public,anon,authenticated;

create or replace function public.process_market_tick()
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_clock public.economy_clock; v_time timestamptz:=clock_timestamp();
 v_product record; v_stock integer; v_demand integer; v_supply integer;
 v_demand_modifier numeric; v_supply_modifier numeric; v_target numeric;
 v_market bigint; v_wholesale bigint; v_trend numeric; v_wait integer;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if not exists(select 1 from public.stores where user_id=auth.uid()) then raise exception 'Store required' using errcode='W0001'; end if;
 -- Global clock first, products by UUID next. This function never locks a store or inventory.
 select * into v_clock from public.economy_clock where id=true for update;
 v_time:=clock_timestamp();
 v_wait:=greatest(0,ceil(300-extract(epoch from v_time-v_clock.last_tick_at))::integer);
 if v_wait>0 then return jsonb_build_object('updated',false,'wait_seconds',v_wait,'tick',v_clock.tick); end if;
 -- Exactly one step regardless of the elapsed offline time.
 for v_product in select p.*,e.reference_market_kurus,e.reference_wholesale_kurus,e.reference_demand,e.reference_supply,e.target_stock
  from public.products p join public.product_economy e on e.product_id=p.id where p.active order by p.id for update of p
 loop
  -- Slow deterministic category cycle, shared by every player. Events are Phase 9.
  v_trend:=0.20*sin((v_clock.tick+1)::numeric/6+ascii(left(v_product.category,1))::numeric/10);
  v_demand:=greatest(0,least(100,round(v_product.reference_demand*(1+v_trend))::integer));
  -- Supplier replenishment is capped at 5% of target per step, never a full offline refill.
  v_stock:=case when v_product.system_stock<v_product.target_stock then least(v_product.target_stock,v_product.system_stock+greatest(1,ceil(v_product.target_stock*0.05)::integer)) else v_product.system_stock end;
  v_supply:=greatest(0,least(100,round(v_product.reference_supply*least(2,v_stock::numeric/v_product.target_stock))::integer));
  v_demand_modifier:=case when v_product.reference_demand=0 then 1 else v_demand::numeric/v_product.reference_demand end;
  v_supply_modifier:=least(1.5,greatest(0.75,1+(1-v_stock::numeric/v_product.target_stock)*0.5));
  -- Baseline market price = product base price times its original retail markup.
  -- Event modifier is 1 in this phase. Hard floor/ceiling 50%/200% of baseline.
  v_target:=v_product.reference_market_kurus*v_demand_modifier*v_supply_modifier;
  v_market:=greatest(1,least(1000000000000,
   greatest(ceil(v_product.market_price_kurus*0.95),ceil(v_product.reference_market_kurus*0.5),
    least(floor(v_product.market_price_kurus*1.05),floor(v_product.reference_market_kurus*2.0),round(v_target)))))::bigint;
  -- Preserve original wholesale/retail ratio, independently cap movement at 5%.
  v_wholesale:=greatest(1,least(1000000000000,
   greatest(ceil(v_product.wholesale_price_kurus*0.95),ceil(v_product.reference_wholesale_kurus*0.5),
    least(floor(v_product.wholesale_price_kurus*1.05),floor(v_product.reference_wholesale_kurus*2.0),
     round(v_market::numeric*v_product.reference_wholesale_kurus/v_product.reference_market_kurus)))))::bigint;
  update public.products set market_price_kurus=v_market,wholesale_price_kurus=v_wholesale,demand=v_demand,supply=v_supply,system_stock=v_stock where id=v_product.id;
  insert into public.price_history(product_id,tick,recorded_at,market_price_kurus,wholesale_price_kurus,demand,supply,system_stock)
   values(v_product.id,v_clock.tick+1,v_time,v_market,v_wholesale,v_demand,v_supply,v_stock);
 end loop;
 update public.economy_clock set last_tick_at=v_time,tick=tick+1 where id=true;
 return jsonb_build_object('updated',true,'wait_seconds',300,'tick',v_clock.tick+1);
end;
$$;
revoke all on function public.process_market_tick() from public,anon,authenticated;
grant execute on function public.process_market_tick() to authenticated;

create or replace function public.market_snapshot(p_product_id uuid default null,p_window text default '24H')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb; v_product uuid; v_seconds integer; v_bucket integer;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if not exists(select 1 from public.stores where user_id=auth.uid()) then raise exception 'Store required' using errcode='W0001'; end if;
 case p_window when '1H' then v_seconds:=3600;v_bucket:=60;
 when '24H' then v_seconds:=86400;v_bucket:=300;
 when '7D' then v_seconds:=604800;v_bucket:=3600;
 when '30D' then v_seconds:=2592000;v_bucket:=14400;
 else raise exception 'Invalid history window' using errcode='E0001';end case;
 if p_product_id is null then select id into v_product from public.products where active order by category,name limit 1;
 else select id into v_product from public.products where active and id=p_product_id;
 if not found then raise exception 'Product unavailable' using errcode='W0002';end if;end if;
 select jsonb_build_object('as_of',now(),'tick',c.tick,'next_tick_at',c.last_tick_at+interval '5 minutes','selected_product',v_product,'window',p_window,
 'products',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'category',p.category,'market_price_kurus',p.market_price_kurus::text,'wholesale_price_kurus',p.wholesale_price_kurus::text,'demand',p.demand,'supply',p.supply,'system_stock',p.system_stock,
 'change_pct',round((p.market_price_kurus::numeric/e.reference_market_kurus-1)*100,2)) order by p.category,p.name),'[]'::jsonb) from public.products p join public.product_economy e on e.product_id=p.id where p.active),
 'categories',(select coalesce(jsonb_agg(jsonb_build_object('category',t.category,'change_pct',t.change_pct,'demand',t.demand,'supply',t.supply) order by t.category),'[]'::jsonb) from
 (select p.category,round(avg((p.market_price_kurus::numeric/e.reference_market_kurus-1)*100),2) change_pct,round(avg(p.demand)) demand,round(avg(p.supply)) supply from public.products p join public.product_economy e on e.product_id=p.id where p.active group by p.category) t),
 'history',(select coalesce(jsonb_agg(jsonb_build_object('recorded_at',h.recorded_at,'market_price_kurus',h.market_price_kurus::text,'wholesale_price_kurus',h.wholesale_price_kurus::text) order by h.recorded_at),'[]'::jsonb) from
 (select distinct on (floor(extract(epoch from recorded_at)/v_bucket)) recorded_at,market_price_kurus,wholesale_price_kurus from public.price_history where product_id=v_product and recorded_at>=now()-make_interval(secs=>v_seconds) order by floor(extract(epoch from recorded_at)/v_bucket),recorded_at desc,tick desc) h)
 ) into v_result from public.economy_clock c where id=true;
 return v_result;
end;
$$;
revoke all on function public.market_snapshot(uuid,text) from public,anon,authenticated;
grant execute on function public.market_snapshot(uuid,text) to authenticated;
commit;
