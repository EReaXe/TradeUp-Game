-- Phase 7: reservations retain owned warehouse capacity/value. No destructive resets.
begin;
alter table public.inventory add column if not exists reserved_quantity integer not null default 0 check(reserved_quantity between 0 and quantity);
create table if not exists public.economy_settings(id boolean primary key default true check(id),marketplace_fee_bps integer not null check(marketplace_fee_bps between 0 and 10000));
insert into public.economy_settings values(true,500) on conflict(id) do nothing;
alter table public.economy_settings enable row level security;
revoke all on public.economy_settings from public,anon,authenticated;
create table if not exists public.marketplace_listings (
 id uuid primary key default gen_random_uuid(),seller_store_id uuid not null references public.stores(id),product_id uuid not null references public.products(id),
 quantity integer not null check(quantity between 0 and 1000),original_quantity integer not null check(original_quantity between 1 and 1000),
 unit_price_kurus bigint not null check(unit_price_kurus between 1 and 1000000000000),status text not null default 'active' check(status in ('active','sold','cancelled')),
 request_id uuid not null,created_at timestamptz not null default now(),unique(seller_store_id,request_id)
);
create index if not exists marketplace_active_date on public.marketplace_listings(status,created_at desc);
create table if not exists public.marketplace_receipts (
 buyer_store_id uuid not null references public.stores(id),seller_store_id uuid not null references public.stores(id),request_id uuid not null,
 listing_id uuid not null references public.marketplace_listings(id),quantity integer not null check(quantity between 1 and 1000),unit_price_kurus bigint not null,
 total_kurus bigint not null,fee_kurus bigint not null,created_at timestamptz not null default now(),primary key(buyer_store_id,request_id)
);
alter table public.marketplace_listings enable row level security;
alter table public.marketplace_receipts enable row level security;
revoke all on public.marketplace_listings,public.marketplace_receipts from public,anon,authenticated;
grant select on public.marketplace_listings,public.marketplace_receipts to authenticated;
drop policy if exists marketplace_listings_read on public.marketplace_listings;
create policy marketplace_listings_read on public.marketplace_listings for select to authenticated using(status='active' or exists(select 1 from public.stores s where s.id=seller_store_id and s.user_id=(select auth.uid())));
drop policy if exists marketplace_receipts_read_own on public.marketplace_receipts;
create policy marketplace_receipts_read_own on public.marketplace_receipts for select to authenticated using(exists(select 1 from public.stores s where s.id in(buyer_store_id,seller_store_id) and s.user_id=(select auth.uid())));
drop trigger if exists marketplace_receipts_immutable on public.marketplace_receipts;
create trigger marketplace_receipts_immutable before update or delete on public.marketplace_receipts for each row execute function public.reject_ledger_mutation();
create or replace function public.create_marketplace_listing(p_product_id uuid,p_quantity integer,p_price_kurus bigint,p_request_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare s public.stores; l public.marketplace_listings; i public.inventory;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if p_quantity is null or p_quantity not between 1 and 1000 or p_price_kurus is null or p_price_kurus not between 1 and 1000000000000 or p_request_id is null or p_product_id is null then raise exception 'Invalid request' using errcode='M0001'; end if;
 select * into s from public.stores where user_id=auth.uid() for update;
 if not found then raise exception 'Store not found' using errcode='P0002'; end if;
 select * into l from public.marketplace_listings where seller_store_id=s.id and request_id=p_request_id;
 if found then
  if l.product_id<>p_product_id or l.original_quantity<>p_quantity or l.unit_price_kurus<>p_price_kurus then raise exception 'Request mismatch' using errcode='M0008'; end if;
  return l.id;
 end if;
 if (select count(*) from public.marketplace_listings where seller_store_id=s.id and status='active')>=s.listing_limit then raise exception 'Listing limit reached' using errcode='M0002'; end if;
 select * into i from public.inventory where store_id=s.id and product_id=p_product_id;
 if not found or i.quantity-i.reserved_quantity<p_quantity then raise exception 'Available stock required' using errcode='M0003'; end if;
 update public.inventory set reserved_quantity=reserved_quantity+p_quantity,updated_at=now() where store_id=s.id and product_id=p_product_id;
 insert into public.marketplace_listings(seller_store_id,product_id,quantity,original_quantity,unit_price_kurus,request_id) values(s.id,p_product_id,p_quantity,p_quantity,p_price_kurus,p_request_id) returning id into l.id;
 return l.id;
end;
$$;
create or replace function public.cancel_marketplace_listing(p_listing_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare s public.stores; l public.marketplace_listings;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
 select * into s from public.stores where user_id=auth.uid() for update;
 if not found then raise exception 'Store not found' using errcode='P0002'; end if;
 select * into l from public.marketplace_listings where id=p_listing_id for update;
 if not found or l.seller_store_id<>s.id then raise exception 'Listing not owned' using errcode='M0004'; end if;
 if l.status<>'active' then return; end if;
 update public.inventory set reserved_quantity=reserved_quantity-l.quantity,updated_at=now() where store_id=s.id and product_id=l.product_id;
 update public.marketplace_listings set status='cancelled',quantity=0 where id=l.id;
end;
$$;
create or replace function public.buy_marketplace_listing(p_listing_id uuid,p_quantity integer,p_expected_price_kurus bigint,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.stores; s public.stores; l public.marketplace_listings; r public.marketplace_receipts; i public.inventory; si public.inventory; seller uuid; buyer uuid; total bigint; fee bigint; bps integer; units bigint; avg_cost bigint;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if p_quantity is null or p_quantity not between 1 and 1000 or p_expected_price_kurus is null or p_expected_price_kurus<=0 or p_request_id is null or p_listing_id is null then raise exception 'Invalid request' using errcode='M0001'; end if;
 select id into buyer from public.stores where user_id=auth.uid();
 select seller_store_id into seller from public.marketplace_listings where id=p_listing_id;
 if buyer is null then raise exception 'Store not found' using errcode='P0002'; end if;
 if seller is null then raise exception 'Listing unavailable' using errcode='M0005'; end if;
 if seller=buyer then raise exception 'Cannot buy own listing' using errcode='M0007'; end if;
 -- Deterministic store lock order, then listing. Matches single-store wholesale/NPC operations.
 perform id from public.stores where id in(buyer,seller) order by id for update;
 select * into b from public.stores where id=buyer;
 select * into s from public.stores where id=seller;
 select * into r from public.marketplace_receipts where buyer_store_id=buyer and request_id=p_request_id;
 if found then
  if r.listing_id<>p_listing_id or r.quantity<>p_quantity or r.unit_price_kurus<>p_expected_price_kurus then raise exception 'Request mismatch' using errcode='M0008'; end if;
 else
  select * into l from public.marketplace_listings where id=p_listing_id for update;
  if l.status<>'active' or l.quantity<p_quantity then raise exception 'Listing unavailable' using errcode='M0005'; end if;
  if l.unit_price_kurus<>p_expected_price_kurus then raise exception 'Price changed' using errcode='M0006'; end if;
  total:=l.unit_price_kurus*p_quantity::bigint;
  if b.cash_kurus<total then raise exception 'Insufficient balance' using errcode='W0005'; end if;
  select coalesce(sum(quantity),0) into units from public.inventory where store_id=b.id;
  if units+p_quantity>b.warehouse_capacity then raise exception 'Warehouse full' using errcode='W0006'; end if;
  if s.cash_kurus>9000000000000000-total then raise exception 'Seller balance limit' using errcode='M0009'; end if;
  select marketplace_fee_bps into bps from public.economy_settings where id;
  if bps is null then raise exception 'Missing fee config'; end if;
  fee:=round(total::numeric*bps/10000)::bigint;
  select * into si from public.inventory where store_id=s.id and product_id=l.product_id;
  if si.reserved_quantity<p_quantity or si.quantity<p_quantity then raise exception 'Reserved stock unavailable' using errcode='M0005'; end if;
  select * into i from public.inventory where store_id=b.id and product_id=l.product_id;
  avg_cost:=round((coalesce(i.quantity,0)::numeric*coalesce(i.average_cost_kurus,0)+total)/(coalesce(i.quantity,0)+p_quantity))::bigint;
  update public.inventory set quantity=quantity-p_quantity,reserved_quantity=reserved_quantity-p_quantity,updated_at=now() where store_id=s.id and product_id=l.product_id;
  insert into public.inventory(store_id,product_id,quantity,average_cost_kurus) values(b.id,l.product_id,p_quantity,avg_cost)
  on conflict(store_id,product_id) do update set quantity=inventory.quantity+excluded.quantity,average_cost_kurus=excluded.average_cost_kurus,updated_at=now();
  update public.stores set cash_kurus=cash_kurus-total where id=b.id;
  update public.stores set cash_kurus=cash_kurus+total-fee where id=s.id;
  update public.marketplace_listings set quantity=quantity-p_quantity,status=case when quantity=p_quantity then 'sold' else 'active' end where id=l.id;
  insert into public.transactions(user_id,store_id,type,amount_kurus,balance_after_kurus,reference_id,idempotency_key) values(b.user_id,b.id,'MARKETPLACE_PURCHASE',-total,b.cash_kurus-total,l.product_id,'mp-buy:'||p_request_id::text);
  insert into public.transactions(user_id,store_id,type,amount_kurus,balance_after_kurus,reference_id,idempotency_key,sale_quantity,cost_of_goods_kurus) values(s.user_id,s.id,'MARKETPLACE_SALE',total,s.cash_kurus+total,l.product_id,'mp-sale:'||p_request_id::text||':'||b.id::text,p_quantity,si.average_cost_kurus*p_quantity::bigint);
  if fee>0 then insert into public.transactions(user_id,store_id,type,amount_kurus,balance_after_kurus,reference_id,idempotency_key) values(s.user_id,s.id,'MARKETPLACE_FEE',-fee,s.cash_kurus+total-fee,l.product_id,'mp-fee:'||p_request_id::text||':'||b.id::text); end if;
  insert into public.marketplace_receipts values(b.id,s.id,p_request_id,l.id,p_quantity,l.unit_price_kurus,total,fee,now()) returning * into r;
 end if;
 return jsonb_build_object('quantity',r.quantity,'total_kurus',r.total_kurus::text,'fee_kurus',r.fee_kurus::text,'seller_gets_kurus',(r.total_kurus-r.fee_kurus)::text);
end;
$$;
create or replace function public.my_marketplace(p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s public.stores; listings jsonb; owned jsonb; items jsonb; n bigint; bps integer;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if p_offset is null or p_offset not between 0 and 1000000 then raise exception 'Invalid offset' using errcode='M0001'; end if;
 select * into s from public.stores where user_id=auth.uid();if not found then raise exception 'Store not found' using errcode='P0002'; end if;
 select marketplace_fee_bps into bps from public.economy_settings where id;
 select count(*) into n from public.marketplace_listings where status='active';
 select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'name',p.name,'rarity',p.rarity,'seller',st.store_name,'mine',l.seller_store_id=s.id,'quantity',l.quantity,'price_kurus',l.unit_price_kurus::text,'market_price_kurus',p.market_price_kurus::text) order by l.created_at desc,l.id),'[]'::jsonb) into listings
 from (select * from public.marketplace_listings where status='active' order by created_at desc,id offset p_offset limit 50) l join public.products p on p.id=l.product_id join public.stores st on st.id=l.seller_store_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'name',p.name,'quantity',l.quantity,'price_kurus',l.unit_price_kurus::text) order by l.created_at desc),'[]'::jsonb) into owned from public.marketplace_listings l join public.products p on p.id=l.product_id where l.seller_store_id=s.id and l.status='active';
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'available',i.quantity-i.reserved_quantity,'market_price_kurus',p.market_price_kurus::text) order by p.name),'[]'::jsonb) into items from public.inventory i join public.products p on p.id=i.product_id where i.store_id=s.id and i.quantity>i.reserved_quantity;
 return jsonb_build_object('listings',listings,'owned',owned,'items',items,'total',n,'fee_bps',bps,'listing_limit',s.listing_limit);
end;
$$;
revoke all on function public.create_marketplace_listing(uuid,integer,bigint,uuid),public.cancel_marketplace_listing(uuid),public.buy_marketplace_listing(uuid,integer,bigint,uuid),public.my_marketplace(integer) from public,anon,authenticated;
grant execute on function public.create_marketplace_listing(uuid,integer,bigint,uuid),public.cancel_marketplace_listing(uuid),public.buy_marketplace_listing(uuid,integer,bigint,uuid),public.my_marketplace(integer) to authenticated;
create or replace function public.set_npc_listing(p_product_id uuid,p_price_kurus bigint,p_enabled boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_store public.stores; v_count integer;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if p_product_id is null or p_price_kurus is null or p_price_kurus not between 1 and 1000000000000 or p_enabled is null then raise exception 'Invalid price' using errcode='N0001'; end if;
 select * into v_store from public.stores where user_id=auth.uid() for update;
 if not found then raise exception 'Store not found' using errcode='P0002'; end if;
 if not exists(select 1 from public.inventory where store_id=v_store.id and product_id=p_product_id and quantity>reserved_quantity) and (p_enabled or not exists(select 1 from public.npc_listings where store_id=v_store.id and product_id=p_product_id)) then raise exception 'Owned stock required' using errcode='N0002'; end if;
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
 for v_row in select l.product_id,l.price_kurus,i.quantity-i.reserved_quantity as quantity,i.average_cost_kurus,p.market_price_kurus,p.demand
 from public.npc_listings l join public.inventory i on i.store_id=l.store_id and i.product_id=l.product_id join public.products p on p.id=l.product_id
 where l.store_id=v_store.id and l.enabled and i.quantity>i.reserved_quantity order by l.product_id loop
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
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'quantity',i.quantity-i.reserved_quantity,'market_price_kurus',p.market_price_kurus::text,'average_cost_kurus',i.average_cost_kurus::text,'price_kurus',coalesce(l.price_kurus,p.market_price_kurus)::text,'enabled',coalesce(l.enabled,false)) order by p.name),'[]'::jsonb) into v_items
 from public.inventory i join public.products p on p.id=i.product_id left join public.npc_listings l on l.store_id=i.store_id and l.product_id=i.product_id
 where i.store_id=v_store.id and i.quantity>i.reserved_quantity;
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
 select v_profit+coalesce(sum(amount_kurus),0) into v_profit from public.transactions where store_id=v_store.id and type='MARKETPLACE_FEE' and created_at>=v_day and created_at<=now();
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

create or replace function public.my_inventory()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 v_user uuid := auth.uid();
 v_store public.stores;
 v_items jsonb;
 v_units numeric;
 v_cost numeric;
 v_value numeric;
begin
 if v_user is null then raise exception 'Authentication required' using errcode='28000'; end if;
 select * into v_store from public.stores where user_id=v_user;
 if not found then raise exception 'Store not found' using errcode='P0002'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
 'product_id',p.id,'name',p.name,'category',p.category,'rarity',p.rarity,'active',p.active,
 'quantity',i.quantity,'reserved',i.reserved_quantity,'available',i.quantity-i.reserved_quantity,'average_cost_kurus',i.average_cost_kurus::text,'market_price_kurus',p.market_price_kurus::text,
 'cost_kurus',(i.quantity::numeric*i.average_cost_kurus)::text,
 'value_kurus',(i.quantity::numeric*p.market_price_kurus)::text,
 'potential_profit_kurus',(i.quantity::numeric*(p.market_price_kurus-i.average_cost_kurus))::text
 ) order by p.name),'[]'::jsonb),
 coalesce(sum(i.quantity),0),coalesce(sum(i.quantity::numeric*i.average_cost_kurus),0),coalesce(sum(i.quantity::numeric*p.market_price_kurus),0)
 into v_items,v_units,v_cost,v_value
 from public.inventory i join public.products p on p.id=i.product_id where i.store_id=v_store.id and i.quantity>0;
 return jsonb_build_object('as_of',now(),'store_name',v_store.store_name,'warehouse_capacity',v_store.warehouse_capacity,
 'units',v_units::text,'cost_kurus',v_cost::text,'value_kurus',v_value::text,'potential_profit_kurus',(v_value-v_cost)::text,'items',v_items);
end;
$$;
revoke all on function public.my_inventory() from public,anon,authenticated;
grant execute on function public.my_inventory() to authenticated;

commit;
