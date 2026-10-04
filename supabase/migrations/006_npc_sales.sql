-- Phase 6. Online simulation only; no offline catch-up.
begin;
alter table public.stores add column if not exists last_npc_tick_at timestamptz;
alter table public.transactions add column if not exists sale_quantity integer check(sale_quantity>0);
alter table public.transactions add column if not exists cost_of_goods_kurus bigint check(cost_of_goods_kurus>=0);
create table if not exists public.npc_listings (
 store_id uuid not null references public.stores(id),
 product_id uuid not null references public.products(id),
 price_kurus bigint not null check(price_kurus between 1 and 1000000000000),
 enabled boolean not null default true,
 primary key(store_id,product_id)
);
alter table public.npc_listings enable row level security;
revoke all on public.npc_listings from public,anon,authenticated;
grant select on public.npc_listings to authenticated;
drop policy if exists npc_listings_read_own on public.npc_listings;
create policy npc_listings_read_own on public.npc_listings for select to authenticated using(exists(select 1 from public.stores s where s.id=npc_listings.store_id and s.user_id=(select auth.uid())));
create or replace function public.set_npc_listing(p_product_id uuid,p_price_kurus bigint,p_enabled boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_store public.stores; v_count integer;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if p_product_id is null or p_price_kurus is null or p_price_kurus not between 1 and 1000000000000 or p_enabled is null then raise exception 'Invalid price' using errcode='N0001'; end if;
 select * into v_store from public.stores where user_id=auth.uid() for update;
 if not found then raise exception 'Store not found' using errcode='P0002'; end if;
 if not exists(select 1 from public.inventory where store_id=v_store.id and product_id=p_product_id and quantity>0) and (p_enabled or not exists(select 1 from public.npc_listings where store_id=v_store.id and product_id=p_product_id)) then raise exception 'Owned stock required' using errcode='N0002'; end if;
 if p_enabled and not exists(select 1 from public.npc_listings where store_id=v_store.id and product_id=p_product_id and enabled) then
  select count(*) into v_count from public.npc_listings where store_id=v_store.id and enabled;
  if v_count>=v_store.listing_limit then raise exception 'Listing limit reached' using errcode='N0003'; end if;
 end if;
 insert into public.npc_listings values(v_store.id,p_product_id,p_price_kurus,p_enabled)
 on conflict(store_id,product_id) do update set price_kurus=excluded.price_kurus,enabled=excluded.enabled;
end;
$$;
create or replace function public.process_npc_sales()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_store public.stores; v_row record; v_probability numeric; v_sold integer:=0; v_revenue numeric:=0; v_cost numeric:=0; v_balance bigint;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
 select * into v_store from public.stores where user_id=auth.uid() for update;
 if not found then raise exception 'Store not found' using errcode='P0002'; end if;
 if v_store.last_npc_tick_at is null or now()-v_store.last_npc_tick_at>interval '120 seconds' then
  update public.stores set last_npc_tick_at=now() where id=v_store.id;
  return jsonb_build_object('sold',0,'revenue_kurus','0','profit_kurus','0','wait_seconds',60);
 end if;
 if now()-v_store.last_npc_tick_at<interval '60 seconds' then
  return jsonb_build_object('sold',0,'revenue_kurus','0','profit_kurus','0','wait_seconds',ceil(extract(epoch from v_store.last_npc_tick_at+interval '60 seconds'-now())));
 end if;
 update public.stores set last_npc_tick_at=now() where id=v_store.id;
 for v_row in select l.product_id,l.price_kurus,i.quantity,i.average_cost_kurus,p.market_price_kurus,p.demand
 from public.npc_listings l join public.inventory i on i.store_id=l.store_id and i.product_id=l.product_id join public.products p on p.id=l.product_id
 where l.store_id=v_store.id and l.enabled and i.quantity>0 order by l.product_id loop
  v_probability:=least(1::numeric,(v_row.demand/100.0)*power(v_row.market_price_kurus::numeric/v_row.price_kurus,2)*(0.5+v_store.reputation/200.0));
  if random()<v_probability and v_store.cash_kurus<=9000000000000000-v_row.price_kurus then
   update public.inventory set quantity=quantity-1,updated_at=now() where store_id=v_store.id and product_id=v_row.product_id;
   update public.stores set cash_kurus=cash_kurus+v_row.price_kurus,reputation=least(100,reputation+1) where id=v_store.id returning cash_kurus into v_balance;
   insert into public.transactions(user_id,store_id,type,amount_kurus,balance_after_kurus,reference_id,idempotency_key,sale_quantity,cost_of_goods_kurus)
   values(v_store.user_id,v_store.id,'NPC_SALE',v_row.price_kurus,v_balance,v_row.product_id,'npc:'||gen_random_uuid()::text,1,v_row.average_cost_kurus);
   v_store.cash_kurus:=v_balance;v_sold:=v_sold+1;v_revenue:=v_revenue+v_row.price_kurus;v_cost:=v_cost+v_row.average_cost_kurus;
   if v_row.quantity=1 then update public.npc_listings set enabled=false where store_id=v_store.id and product_id=v_row.product_id; end if;
  end if;
 end loop;
 return jsonb_build_object('sold',v_sold,'revenue_kurus',v_revenue::text,'profit_kurus',(v_revenue-v_cost)::text,'wait_seconds',60);
end;
$$;
create or replace function public.my_sales_state()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_store public.stores; v_items jsonb; v_orders jsonb;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
 select * into v_store from public.stores where user_id=auth.uid();
 if not found then raise exception 'Store not found' using errcode='P0002'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'quantity',i.quantity,'market_price_kurus',p.market_price_kurus::text,'average_cost_kurus',i.average_cost_kurus::text,'price_kurus',coalesce(l.price_kurus,p.market_price_kurus)::text,'enabled',coalesce(l.enabled,false)) order by p.name),'[]'::jsonb) into v_items
 from public.inventory i join public.products p on p.id=i.product_id left join public.npc_listings l on l.store_id=i.store_id and l.product_id=i.product_id
 where i.store_id=v_store.id and i.quantity>0;
 select coalesce(jsonb_agg(jsonb_build_object('name',coalesce(p.name,'Ürün'),'quantity',t.sale_quantity,'revenue_kurus',t.amount_kurus::text,'profit_kurus',(t.amount_kurus-t.cost_of_goods_kurus)::text,'created_at',t.created_at) order by t.created_at desc,t.id desc),'[]'::jsonb) into v_orders
 from (select * from public.transactions where store_id=v_store.id and type='NPC_SALE' order by created_at desc,id desc limit 20) t left join public.products p on p.id=t.reference_id;
 return jsonb_build_object('items',v_items,'orders',v_orders,'listing_limit',v_store.listing_limit);
end;
$$;
revoke all on function public.set_npc_listing(uuid,bigint,boolean),public.process_npc_sales(),public.my_sales_state() from public,anon,authenticated;
grant execute on function public.set_npc_listing(uuid,bigint,boolean),public.process_npc_sales(),public.my_sales_state() to authenticated;
create or replace function public.my_dashboard()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 v_user uuid := auth.uid();
 v_store public.stores;
 v_day timestamptz := date_trunc('day',now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
 v_revenue numeric;
 v_profit numeric;
 v_orders bigint;
 v_units numeric;
 v_value numeric;
 v_cost numeric;
 v_activity jsonb;
 v_history jsonb;
begin
 if v_user is null then raise exception 'Authentication required' using errcode='28000'; end if;
 select * into v_store from public.stores where user_id=v_user;
 if not found then raise exception 'Store not found' using errcode='P0002'; end if;
 select coalesce(sum(amount_kurus),0),count(*) into v_revenue,v_orders
 from public.transactions where store_id=v_store.id and type in ('NPC_SALE','MARKETPLACE_SALE') and created_at>=v_day and created_at<=now();
 select case when count(*) filter(where cost_of_goods_kurus is null)>0 then null else coalesce(sum(amount_kurus-cost_of_goods_kurus),0) end into v_profit
 from public.transactions where store_id=v_store.id and type in ('NPC_SALE','MARKETPLACE_SALE') and created_at>=v_day and created_at<=now();
 select coalesce(sum(i.quantity),0),coalesce(sum(i.quantity::numeric*p.market_price_kurus),0),coalesce(sum(i.quantity::numeric*i.average_cost_kurus),0)
 into v_units,v_value,v_cost from public.inventory i join public.products p on p.id=i.product_id where i.store_id=v_store.id;
 select coalesce(jsonb_agg(jsonb_build_object('type',t.type,'amount_kurus',t.amount_kurus::text,'created_at',t.created_at) order by t.created_at desc,t.id desc),'[]'::jsonb)
 into v_activity from (select * from public.transactions where store_id=v_store.id order by created_at desc,id desc limit 6) t;
 select jsonb_agg(jsonb_build_object('date',d.bucket::date,'revenue_kurus',coalesce(t.revenue,0)::text,'orders',coalesce(t.orders,0)::text) order by d.bucket)
 into v_history from generate_series((v_day at time zone 'Europe/Istanbul')-interval '6 days',v_day at time zone 'Europe/Istanbul',interval '1 day') d(bucket)
 left join (
  select (created_at at time zone 'Europe/Istanbul')::date as bucket,sum(amount_kurus) revenue,count(*) orders from public.transactions
  where store_id=v_store.id and type in ('NPC_SALE','MARKETPLACE_SALE')
  and created_at>=v_day-interval '6 days' and created_at<=now() group by 1
 ) t on t.bucket=d.bucket::date;
 return jsonb_build_object(
 'as_of',now(),'timezone','Europe/Istanbul','store_name',v_store.store_name,
 'cash_kurus',v_store.cash_kurus::text,
 'net_worth_kurus',(v_store.cash_kurus::numeric+v_value+v_store.business_assets_kurus-v_store.debt_kurus)::text,
 'revenue_kurus',v_revenue::text,'orders',v_orders::text,
 -- Missing legacy sale costs remain unknown; new NPC sales record actual COGS.
 'profit_kurus',v_profit::text,
 'inventory_units',v_units::text,'inventory_value_kurus',v_value::text,'inventory_cost_kurus',v_cost::text,
 'warehouse_capacity',v_store.warehouse_capacity,'level',v_store.level,'reputation',v_store.reputation,
 'activity',v_activity,'history',v_history);
end;
$$;
revoke all on function public.my_dashboard() from public,anon,authenticated;
grant execute on function public.my_dashboard() to authenticated;

commit;
