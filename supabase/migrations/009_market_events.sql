-- Phase 9, after 008. Event and offer schedules use server time, never client time.
begin;
-- Serialize deployment/reapply with the running global economy before touching products.
do $$begin perform id from public.economy_clock where id=true for update;end;$$;
create table if not exists public.market_schedule (
 id boolean primary key default true check(id),anchor_at timestamptz not null default now()
);
insert into public.market_schedule(id) values(true) on conflict do nothing;
create table if not exists public.market_events (
 id uuid primary key default gen_random_uuid(),slot bigint not null unique check(slot>=0),
 title text not null,news text not null,
 category text not null check(category in ('Technology','Gaming','Clothing','Cosmetics','Sports','Stationery','Home','Collectibles')),
 starts_at timestamptz not null,ends_at timestamptz not null check(ends_at>starts_at),
 supply_bps integer not null check(supply_bps between 1000 and 20000),
 demand_bps integer not null check(demand_bps between 1000 and 20000),
 price_bps integer not null check(price_bps between 5000 and 20000)
);
create table if not exists public.market_drop_products(product_id uuid primary key references public.products(id));
insert into public.products(id,name,category,subcategory,base_price_kurus,wholesale_price_kurus,market_price_kurus,rarity,quality,demand,supply,system_stock)
 values('00000000-0000-4000-8000-000000000101','Founder Limited Mouse','Collectibles','Limited Drops',225000,180000,252000,'Legendary',90,80,20,0) on conflict do nothing;
insert into public.market_drop_products values('00000000-0000-4000-8000-000000000101') on conflict do nothing;
insert into public.product_economy select id,market_price_kurus,wholesale_price_kurus,demand,supply,25 from public.products where id='00000000-0000-4000-8000-000000000101' on conflict do nothing;
insert into public.price_history(product_id,tick,market_price_kurus,wholesale_price_kurus,demand,supply,system_stock)
 select p.id,c.tick,p.market_price_kurus,p.wholesale_price_kurus,p.demand,p.supply,p.system_stock from public.products p cross join public.economy_clock c where p.id='00000000-0000-4000-8000-000000000101' on conflict do nothing;
create table if not exists public.market_offers (
 id uuid primary key default gen_random_uuid(),slot bigint not null check(slot>=0),
 kind text not null check(kind in ('FLASH_DEAL','LIMITED_DROP')),
 product_id uuid not null references public.products(id),
 starts_at timestamptz not null,ends_at timestamptz not null check(ends_at>starts_at),
 original_price_kurus bigint not null check(original_price_kurus between 1 and 1000000000000),
 price_kurus bigint not null check(price_kurus between 1 and 1000000000000),
 initial_quantity integer not null check(initial_quantity between 1 and 1000),
 remaining_quantity integer not null check(remaining_quantity between 0 and initial_quantity),
 unique(slot,kind)
);
create table if not exists public.market_offer_receipts (
 store_id uuid not null references public.stores(id),request_id uuid not null,
 offer_id uuid not null references public.market_offers(id),product_id uuid not null references public.products(id),
 quantity integer not null check(quantity between 1 and 1000),unit_price_kurus bigint not null check(unit_price_kurus>0),
 total_kurus bigint not null check(total_kurus>0),balance_after_kurus bigint not null check(balance_after_kurus>=0),
 transaction_id uuid not null unique references public.transactions(id),created_at timestamptz not null default now(),
 primary key(store_id,request_id)
);
create index if not exists market_events_time on public.market_events(starts_at desc);
create index if not exists market_offers_time on public.market_offers(starts_at desc);
alter table public.market_schedule enable row level security;
alter table public.market_events enable row level security;
alter table public.market_drop_products enable row level security;
alter table public.market_offers enable row level security;
alter table public.market_offer_receipts enable row level security;
revoke all on public.market_schedule,public.market_events,public.market_drop_products,public.market_offers,public.market_offer_receipts from public,anon,authenticated;
grant select on public.market_offer_receipts to authenticated;
drop policy if exists offer_receipts_own on public.market_offer_receipts;
create policy offer_receipts_own on public.market_offer_receipts for select to authenticated using(exists(select 1 from public.stores s where s.id=store_id and s.user_id=(select auth.uid())));
drop trigger if exists offer_receipts_immutable on public.market_offer_receipts;
create trigger offer_receipts_immutable before update or delete on public.market_offer_receipts for each row execute function public.reject_ledger_mutation();

-- Private scheduler; caller must hold the global economy_clock row lock.
create or replace function public.ensure_market_schedule(p_time timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare v_anchor timestamptz;v_current bigint;v_slot bigint;v_start timestamptz;v_category text;v_title text;v_news text;v_supply integer;v_demand integer;v_price integer;v_product public.products;
begin
 select anchor_at into v_anchor from public.market_schedule where id=true;
 v_current:=greatest(0,floor(extract(epoch from p_time-v_anchor)/3600)::bigint);
 -- Only this hour and the next: no retroactive offers after an offline gap.
 for v_slot in v_current..v_current+1 loop
  v_start:=v_anchor+v_slot*interval '1 hour';
  case v_slot%4
   when 0 then v_category:='Technology';v_title:='Küresel çip sıkıntısı';v_news:='Teknoloji tedariki daralıyor. Arz %35 azalırken hedef fiyat çarpanı %20 yükseliyor.';v_supply:=6500;v_demand:=10000;v_price:=12000;
   when 1 then v_category:='Gaming';v_title:='Gaming festivali';v_news:='Festival dönemi Gaming ürünlerinde talebi %45 artırıyor.';v_supply:=10000;v_demand:=14500;v_price:=10000;
   when 2 then v_category:='Cosmetics';v_title:='Kozmetik tedarik dalgası';v_news:='Yeni sevkiyatlar kozmetik arzını %25 artırıyor. Hedef fiyat çarpanı %10 geriliyor.';v_supply:=12500;v_demand:=10000;v_price:=9000;
   else v_category:='Sports';v_title:='Spor sezonu açıldı';v_news:='Yeni sezonla spor ürünlerine talep %30 artıyor.';v_supply:=10000;v_demand:=13000;v_price:=10000;
  end case;
  insert into public.market_events(slot,title,news,category,starts_at,ends_at,supply_bps,demand_bps,price_bps)
   values(v_slot,v_title,v_news,v_category,v_start,v_start+interval '45 minutes',v_supply,v_demand,v_price) on conflict(slot) do nothing;
  if not exists(select 1 from public.market_offers where slot=v_slot and kind='FLASH_DEAL') then
   select p.* into v_product from public.products p where p.active and p.rarity in ('Common','Uncommon') and p.system_stock>0 and not exists(select 1 from public.market_drop_products d where d.product_id=p.id)
    order by p.wholesale_price_kurus,p.id offset (v_slot%5) limit 1;
   if found then insert into public.market_offers(slot,kind,product_id,starts_at,ends_at,original_price_kurus,price_kurus,initial_quantity,remaining_quantity)
    values(v_slot,'FLASH_DEAL',v_product.id,v_start,v_start+interval '15 minutes',v_product.wholesale_price_kurus,greatest(1,round(v_product.wholesale_price_kurus*0.70)::bigint),least(100,v_product.system_stock),least(100,v_product.system_stock)) on conflict do nothing;end if;
  end if;
  select * into v_product from public.products where id='00000000-0000-4000-8000-000000000101' and active;
  if found then insert into public.market_offers(slot,kind,product_id,starts_at,ends_at,original_price_kurus,price_kurus,initial_quantity,remaining_quantity)
   values(v_slot,'LIMITED_DROP',v_product.id,v_start,v_start+interval '20 minutes',v_product.wholesale_price_kurus,v_product.wholesale_price_kurus,25,25) on conflict do nothing;end if;
 end loop;
end;
$$;
revoke all on function public.ensure_market_schedule(timestamptz) from public,anon,authenticated;

create or replace function public.market_events_snapshot()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_store uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000';end if;
 select id into v_store from public.stores where user_id=auth.uid();if not found then raise exception 'Store required' using errcode='W0001';end if;
 return jsonb_build_object('as_of',now(),
 'events',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'title',e.title,'news',e.news,'category',e.category,'starts_at',e.starts_at,'ends_at',e.ends_at,'supply_bps',e.supply_bps,'demand_bps',e.demand_bps,'price_bps',e.price_bps) order by e.starts_at desc),'[]'::jsonb) from (select * from public.market_events order by starts_at desc limit 12) e),
 'offers',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'kind',o.kind,'name',p.name,'rarity',p.rarity,'product_id',p.id,'starts_at',o.starts_at,'ends_at',o.ends_at,'price_kurus',o.price_kurus::text,'original_price_kurus',o.original_price_kurus::text,'current_wholesale_price_kurus',p.wholesale_price_kurus::text,'market_price_kurus',p.market_price_kurus::text,'remaining',case when o.kind='FLASH_DEAL' then least(o.remaining_quantity,p.system_stock) else o.remaining_quantity end,'initial_quantity',o.initial_quantity) order by o.starts_at,o.kind),'[]'::jsonb) from public.market_offers o join public.products p on p.id=o.product_id where p.active and o.ends_at>now()),
 'receipts',(select coalesce(jsonb_agg(jsonb_build_object('name',r.name,'quantity',r.quantity,'total_kurus',r.total_kurus::text,'created_at',r.created_at) order by r.created_at desc),'[]'::jsonb) from (select p.name,r.quantity,r.total_kurus,r.created_at from public.market_offer_receipts r join public.products p on p.id=r.product_id where r.store_id=v_store order by r.created_at desc limit 20) r));
end;
$$;
revoke all on function public.market_events_snapshot() from public,anon,authenticated;
grant execute on function public.market_events_snapshot() to authenticated;

create or replace function public.buy_market_offer(p_offer_id uuid,p_quantity integer,p_expected_price_kurus bigint,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_store public.stores;v_offer public.market_offers;v_product public.products;v_product_id uuid;v_receipt public.market_offer_receipts;v_units bigint;v_total bigint;v_average bigint;v_balance bigint;v_tx uuid;v_time timestamptz;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000';end if;
 if p_offer_id is null or p_request_id is null or p_quantity is null or p_quantity not between 1 and 1000 or p_expected_price_kurus is null or p_expected_price_kurus<1 then raise exception 'Invalid request' using errcode='F0001';end if;
 select * into v_store from public.stores where user_id=auth.uid() for update;if not found then raise exception 'Store required' using errcode='W0001';end if;
 select * into v_receipt from public.market_offer_receipts where store_id=v_store.id and request_id=p_request_id;
 if found then
  if v_receipt.offer_id<>p_offer_id or v_receipt.quantity<>p_quantity or v_receipt.unit_price_kurus<>p_expected_price_kurus then raise exception 'Request payload mismatch' using errcode='W0008';end if;
 else
  select product_id into v_product_id from public.market_offers where id=p_offer_id;if not found then raise exception 'Offer unavailable' using errcode='F0002';end if;
  -- Same ordering as wholesale: store -> product -> offer. No global clock lock.
  select * into v_product from public.products where id=v_product_id for update;
  if not found or not v_product.active then raise exception 'Product unavailable' using errcode='W0002';end if;
  select * into v_offer from public.market_offers where id=p_offer_id for update;
  v_time:=clock_timestamp();
  if v_offer.product_id<>v_product_id or v_offer.starts_at>v_time or v_offer.ends_at<=v_time then raise exception 'Offer not active' using errcode='F0002';end if;
  if v_offer.price_kurus<>p_expected_price_kurus then raise exception 'Price changed' using errcode='W0007';end if;
  if v_offer.remaining_quantity<p_quantity or (v_offer.kind='FLASH_DEAL' and v_product.system_stock<p_quantity) then raise exception 'Offer stock insufficient' using errcode='F0003';end if;
  v_total:=v_offer.price_kurus*p_quantity::bigint;
  if v_store.cash_kurus<v_total then raise exception 'Insufficient balance' using errcode='W0005';end if;
  select coalesce(sum(quantity),0) into v_units from public.inventory where store_id=v_store.id;
  if v_units+p_quantity>v_store.warehouse_capacity then raise exception 'Warehouse capacity exceeded' using errcode='W0006';end if;
  select round((coalesce(i.quantity,0)::numeric*coalesce(i.average_cost_kurus,0)+v_total)/(coalesce(i.quantity,0)+p_quantity))::bigint into v_average
   from (select 1) dummy left join public.inventory i on i.store_id=v_store.id and i.product_id=v_product.id;
  update public.stores set cash_kurus=cash_kurus-v_total where id=v_store.id returning cash_kurus into v_balance;
  update public.market_offers set remaining_quantity=remaining_quantity-p_quantity where id=v_offer.id;
  if v_offer.kind='FLASH_DEAL' then update public.products set system_stock=system_stock-p_quantity where id=v_product.id;end if;
  insert into public.inventory(store_id,product_id,quantity,average_cost_kurus) values(v_store.id,v_product.id,p_quantity,v_average)
   on conflict(store_id,product_id) do update set quantity=inventory.quantity+excluded.quantity,average_cost_kurus=excluded.average_cost_kurus,updated_at=now();
  insert into public.transactions(user_id,store_id,type,amount_kurus,balance_after_kurus,reference_id,idempotency_key)
   values(auth.uid(),v_store.id,'WHOLESALE_PURCHASE',-v_total,v_balance,v_product.id,'offer:'||p_request_id::text) returning id into v_tx;
  insert into public.market_offer_receipts(store_id,request_id,offer_id,product_id,quantity,unit_price_kurus,total_kurus,balance_after_kurus,transaction_id)
   values(v_store.id,p_request_id,v_offer.id,v_product.id,p_quantity,v_offer.price_kurus,v_total,v_balance,v_tx) returning * into v_receipt;
 end if;
 return jsonb_build_object('request_id',v_receipt.request_id,'product_id',v_receipt.product_id,'offer_id',v_receipt.offer_id,'quantity',v_receipt.quantity,'unit_price_kurus',v_receipt.unit_price_kurus::text,'total_kurus',v_receipt.total_kurus::text,'balance_after_kurus',v_receipt.balance_after_kurus::text,'transaction_id',v_receipt.transaction_id);
end;
$$;
revoke all on function public.buy_market_offer(uuid,integer,bigint,uuid) from public,anon,authenticated;
grant execute on function public.buy_market_offer(uuid,integer,bigint,uuid) to authenticated;

create or replace function public.process_market_tick()
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_clock public.economy_clock; v_time timestamptz:=clock_timestamp();
 v_product record; v_stock integer; v_demand integer; v_supply integer;
 v_demand_modifier numeric; v_supply_modifier numeric; v_target numeric;
 v_market bigint; v_wholesale bigint; v_trend numeric; v_wait integer;
 v_event_supply integer;v_event_demand integer;v_event_price integer;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if not exists(select 1 from public.stores where user_id=auth.uid()) then raise exception 'Store required' using errcode='W0001'; end if;
 -- Global clock first, products by UUID next. This function never locks a store or inventory.
 select * into v_clock from public.economy_clock where id=true for update;
 v_time:=clock_timestamp();
 perform public.ensure_market_schedule(v_time);
 v_wait:=greatest(0,ceil(300-extract(epoch from v_time-v_clock.last_tick_at))::integer);
 if v_wait>0 then return jsonb_build_object('updated',false,'wait_seconds',v_wait,'tick',v_clock.tick); end if;
 -- Exactly one step regardless of the elapsed offline time.
 for v_product in select p.*,e.reference_market_kurus,e.reference_wholesale_kurus,e.reference_demand,e.reference_supply,e.target_stock
  from public.products p join public.product_economy e on e.product_id=p.id where p.active order by p.id for update of p
 loop
  -- Latest active event in the category wins; modifiers do not stack.
  v_event_supply:=10000;v_event_demand:=10000;v_event_price:=10000;
  select supply_bps,demand_bps,price_bps into v_event_supply,v_event_demand,v_event_price from public.market_events where category=v_product.category and starts_at<=v_time and ends_at>v_time order by starts_at desc,id limit 1;
  v_event_supply:=coalesce(v_event_supply,10000);v_event_demand:=coalesce(v_event_demand,10000);v_event_price:=coalesce(v_event_price,10000);
  v_trend:=0.20*sin((v_clock.tick+1)::numeric/6+ascii(left(v_product.category,1))::numeric/10);
  v_demand:=greatest(0,least(100,round(v_product.reference_demand*(1+v_trend)*v_event_demand/10000)::integer));
  -- Supplier replenishment is capped at 5% of target per step, never a full offline refill.
  v_stock:=case when exists(select 1 from public.market_drop_products d where d.product_id=v_product.id) then v_product.system_stock when v_product.system_stock<v_product.target_stock then least(v_product.target_stock,v_product.system_stock+greatest(1,ceil(v_product.target_stock*0.05*v_event_supply/10000)::integer)) else v_product.system_stock end;
  v_supply:=greatest(0,least(100,round(v_product.reference_supply*least(2,v_stock::numeric/v_product.target_stock)*v_event_supply/10000)::integer));
  v_demand_modifier:=case when v_product.reference_demand=0 then 1 else v_demand::numeric/v_product.reference_demand end;
  v_supply_modifier:=least(1.5,greatest(0.75,1+(1-v_stock::numeric/v_product.target_stock*v_event_supply/10000)*0.5));
  -- Baseline market price = product base price times its original retail markup.
  -- Events affect the target, but never bypass movement or baseline bounds.
  v_target:=v_product.reference_market_kurus*v_demand_modifier*v_supply_modifier*v_event_price/10000;
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



-- Exclude drop-only items from the ordinary supplier; include real price trend.
create or replace function public.wholesale_catalog()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'category',p.category,'rarity',p.rarity,'wholesale_price_kurus',p.wholesale_price_kurus::text,'market_price_kurus',p.market_price_kurus::text,'system_stock',p.system_stock,'demand',p.demand,'quality',p.quality,'change_pct',round((p.market_price_kurus::numeric/e.reference_market_kurus-1)*100,2)) order by p.category,p.name),'[]'::jsonb)
 from public.products p join public.product_economy e on e.product_id=p.id where p.active and not exists(select 1 from public.market_drop_products d where d.product_id=p.id) and auth.uid() is not null;
$$;
revoke all on function public.wholesale_catalog() from public,anon,authenticated;
grant execute on function public.wholesale_catalog() to authenticated;
-- First schedules are created once, without resetting existing quantities on reapply.
do $$begin perform id from public.economy_clock where id=true for update;perform public.ensure_market_schedule(clock_timestamp());end;$$;
commit;
