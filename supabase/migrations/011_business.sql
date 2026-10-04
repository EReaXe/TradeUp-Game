-- Phase 11: prerequisite 010. All prices are integer kurus.
begin;
alter table public.stores add column if not exists warehouse_tier integer not null default 0 check(warehouse_tier between 0 and 4);
alter table public.stores add column if not exists office_tier integer not null default 0 check(office_tier between 0 and 4);
alter table public.stores add column if not exists brand_value integer not null default 0 check(brand_value between 0 and 100);
alter table public.transactions drop constraint if exists transactions_type_check;
alter table public.transactions add constraint transactions_type_check check(type in ('INITIAL_CAPITAL','WHOLESALE_PURCHASE','MARKETPLACE_PURCHASE','MARKETPLACE_SALE','NPC_SALE','MARKETPLACE_FEE','WAREHOUSE_UPGRADE','OFFICE_UPGRADE','ADVERTISEMENT','SALARY','LOAN','LOAN_PAYMENT','REWARD'));
create table if not exists public.business_warehouses(tier integer primary key,label text not null,capacity integer not null,cost_kurus bigint not null,min_level integer not null,xp integer not null);
insert into public.business_warehouses values(0,'Başlangıç deposu',50,0,1,0),(1,'Small Warehouse',250,250000,1,100),(2,'Medium Warehouse',1000,1000000,5,250),(3,'Large Warehouse',5000,5000000,10,500),(4,'Distribution Center',25000,25000000,20,1000) on conflict do nothing;
create table if not exists public.business_offices(tier integer primary key,label text not null,employee_slots integer not null,cost_kurus bigint not null,min_level integer not null,brand_bonus integer not null,xp integer not null);
insert into public.business_offices values(0,'Garage Office',1,0,1,0,0),(1,'Small Office',3,500000,5,5,100),(2,'Business Center',4,2500000,10,10,250),(3,'Corporate HQ',5,10000000,20,20,500),(4,'Mega Campus',6,50000000,30,30,1000) on conflict do nothing;
create table if not exists public.business_ads(code text primary key,label text not null,cost_kurus bigint not null,minutes integer not null,traffic_bps integer not null,conversion_bps integer not null,brand_bonus integer not null);
insert into public.business_ads values('social','Social Media Ads',25000,30,1000,500,1),('search','Search Ads',50000,60,500,1500,2),('influencer','Influencer Campaign',150000,120,2000,1000,4),('brand','Brand Campaign',250000,240,500,500,5) on conflict do nothing;
create table if not exists public.business_roles(code text primary key,label text not null,salary_kurus bigint not null,skill integer not null,conversion_bps integer not null);
insert into public.business_roles values('sales','Sales Specialist',20000,10,1000),('purchasing','Purchasing Specialist',15000,8,400),('warehouse','Warehouse Worker',12500,6,300),('marketing','Marketing Specialist',20000,10,800),('analyst','Market Analyst',17500,5,500),('logistics','Logistics Specialist',15000,7,400) on conflict do nothing;
create table if not exists public.store_campaigns(id uuid primary key default gen_random_uuid(),store_id uuid not null references public.stores(id),code text not null references public.business_ads(code),starts_at timestamptz not null,ends_at timestamptz not null check(ends_at>starts_at));
create index if not exists campaign_store_time on public.store_campaigns(store_id,ends_at);
create table if not exists public.store_employees(store_id uuid not null references public.stores(id),code text not null references public.business_roles(code),level integer not null default 1 check(level=1),paid_until timestamptz not null,primary key(store_id,code));
create table if not exists public.business_receipts(store_id uuid not null references public.stores(id),request_id uuid not null,kind text not null,code text not null,expected_tier integer not null,result jsonb not null,created_at timestamptz not null default now(),primary key(store_id,request_id));
do $$declare t text;begin
 foreach t in array array['business_warehouses','business_offices','business_ads','business_roles','store_campaigns','store_employees','business_receipts'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);end loop;
 foreach t in array array['store_campaigns','store_employees','business_receipts'] loop
 execute format('grant select on public.%I to authenticated',t);execute format('drop policy if exists business_own on public.%I',t);
 execute format('create policy business_own on public.%I for select to authenticated using(exists(select 1 from public.stores s where s.id=store_id and s.user_id=(select auth.uid())))',t);end loop;
end;$$;
drop trigger if exists business_receipt_immutable on public.business_receipts;
create trigger business_receipt_immutable before update or delete on public.business_receipts for each row execute function public.reject_ledger_mutation();
drop trigger if exists campaign_immutable on public.store_campaigns;
create trigger campaign_immutable before update or delete on public.store_campaigns for each row execute function public.reject_ledger_mutation();

create or replace function public.business_effects(p_store uuid,p_at timestamptz)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('brand_value',s.brand_value,'brand_price_bps',10000+s.brand_value*20,
 'employee_conversion_bps',coalesce((select sum(r.conversion_bps) from public.store_employees e join public.business_roles r on r.code=e.code where e.store_id=s.id and e.paid_until>p_at),0),
 'ad_traffic_bps',coalesce((select a.traffic_bps from public.store_campaigns c join public.business_ads a on a.code=c.code where c.store_id=s.id and c.starts_at<=p_at and c.ends_at>p_at order by c.starts_at desc limit 1),0),
 'ad_conversion_bps',coalesce((select a.conversion_bps from public.store_campaigns c join public.business_ads a on a.code=c.code where c.store_id=s.id and c.starts_at<=p_at and c.ends_at>p_at order by c.starts_at desc limit 1),0)) from public.stores s where id=p_store;
$$;
revoke all on function public.business_effects(uuid,timestamptz) from public,anon,authenticated;
create or replace function public.business_npc_probability(p_demand integer,p_market bigint,p_price bigint,p_reputation integer,p_effects jsonb)
returns numeric language sql immutable set search_path='' as $$
 select least(1::numeric,(p_demand/100.0)*power(p_market::numeric/p_price*((p_effects->>'brand_price_bps')::numeric/10000),2)*(0.5+p_reputation/200.0)*
 (1+(p_effects->>'employee_conversion_bps')::numeric/10000)*(1+(p_effects->>'ad_traffic_bps')::numeric/10000)*(1+(p_effects->>'ad_conversion_bps')::numeric/10000));
$$;
revoke all on function public.business_npc_probability(integer,bigint,bigint,integer,jsonb) from public,anon,authenticated;

create or replace function public.business_action(p_kind text,p_code text,p_expected_tier integer,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.stores;r public.business_receipts;w public.business_warehouses;o public.business_offices;a public.business_ads;e public.business_roles;
 v_cost bigint:=0;v_xp integer:=0;v_type text;v_at timestamptz;v_until timestamptz;v_result jsonb;v_count integer;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000';end if;
 if p_kind is null or p_code is null or p_expected_tier is null or p_request_id is null or p_expected_tier not between 0 and 4 then raise exception 'Invalid business request' using errcode='B0001';end if;
 select * into s from public.stores where user_id=auth.uid() for update;if not found then raise exception 'Store required' using errcode='W0001';end if;
 select * into r from public.business_receipts where store_id=s.id and request_id=p_request_id;
 if found then if r.kind<>p_kind or r.code<>p_code or r.expected_tier<>p_expected_tier then raise exception 'Request payload changed' using errcode='B0002';end if;return r.result;end if;
 perform public.sync_store_progression(s.id);select * into s from public.stores where id=s.id;v_at:=clock_timestamp();
 if p_kind='warehouse' then
  if p_code<>'upgrade' or s.warehouse_tier<>p_expected_tier then raise exception 'Warehouse changed' using errcode='B0003';end if;
  select * into w from public.business_warehouses where tier=s.warehouse_tier+1;if not found then raise exception 'Maximum tier' using errcode='B0004';end if;
  if s.level<w.min_level then raise exception 'Level locked' using errcode='B0005';end if;
  v_cost:=w.cost_kurus;v_xp:=w.xp;v_type:='WAREHOUSE_UPGRADE';
 elsif p_kind='office' then
  if p_code<>'upgrade' or s.office_tier<>p_expected_tier then raise exception 'Office changed' using errcode='B0003';end if;
  select * into o from public.business_offices where tier=s.office_tier+1;if not found then raise exception 'Maximum tier' using errcode='B0004';end if;
  if s.level<o.min_level then raise exception 'Level locked' using errcode='B0005';end if;
  v_cost:=o.cost_kurus;v_xp:=o.xp;v_type:='OFFICE_UPGRADE';
 elsif p_kind='campaign' then
  if p_expected_tier<>0 then raise exception 'Invalid tier' using errcode='B0001';end if;
  if s.level<10 then raise exception 'Advertising requires level 10' using errcode='B0005';end if;
  select * into a from public.business_ads where code=p_code;if not found then raise exception 'Unknown campaign' using errcode='B0001';end if;
  if exists(select 1 from public.store_campaigns where store_id=s.id and ends_at>v_at) then raise exception 'Campaign already active' using errcode='B0006';end if;
  v_cost:=a.cost_kurus;v_type:='ADVERTISEMENT';v_until:=v_at+make_interval(mins=>a.minutes);
 elsif p_kind in('hire','fire') then
  if p_expected_tier<>0 then raise exception 'Invalid tier' using errcode='B0001';end if;
  select * into e from public.business_roles where code=p_code;if not found then raise exception 'Unknown employee role' using errcode='B0001';end if;
  if p_kind='hire' then
   if s.level<15 then raise exception 'Employees require level 15' using errcode='B0005';end if;
   if exists(select 1 from public.store_employees where store_id=s.id and code=p_code and paid_until>v_at) then raise exception 'Employee already paid' using errcode='B0007';end if;
   select count(*) into v_count from public.store_employees where store_id=s.id and paid_until>v_at;
   if v_count>=(select employee_slots from public.business_offices where tier=s.office_tier) then raise exception 'Office employee slots full' using errcode='B0008';end if;
   v_cost:=e.salary_kurus;v_type:='SALARY';v_until:=v_at+interval '24 hours';
  else
   if not exists(select 1 from public.store_employees where store_id=s.id and code=p_code and paid_until>v_at) then raise exception 'No active employee' using errcode='B0009';end if;
   v_until:=v_at;
  end if;
 else raise exception 'Invalid action' using errcode='B0001';end if;
 if s.cash_kurus<v_cost then raise exception 'Insufficient cash' using errcode='W0005';end if;
 if p_kind in('warehouse','office') and s.business_assets_kurus>9000000000000000-v_cost/2 then raise exception 'Asset limit' using errcode='B0010';end if;
 update public.stores set cash_kurus=cash_kurus-v_cost where id=s.id;
 if v_cost>0 then insert into public.transactions(user_id,store_id,type,amount_kurus,balance_after_kurus,idempotency_key) values(s.user_id,s.id,v_type,-v_cost,s.cash_kurus-v_cost,'business:'||p_request_id::text);end if;
 if p_kind='warehouse' then update public.stores set warehouse_tier=w.tier,warehouse_capacity=greatest(warehouse_capacity,w.capacity),business_assets_kurus=business_assets_kurus+v_cost/2 where id=s.id;
 elsif p_kind='office' then update public.stores set office_tier=o.tier,brand_value=least(100,brand_value+o.brand_bonus),business_assets_kurus=business_assets_kurus+v_cost/2 where id=s.id;
 elsif p_kind='campaign' then
  insert into public.store_campaigns(store_id,code,starts_at,ends_at) values(s.id,a.code,v_at,v_until);update public.stores set brand_value=least(100,brand_value+a.brand_bonus) where id=s.id;
 else insert into public.store_employees(store_id,code,paid_until) values(s.id,e.code,v_until) on conflict(store_id,code) do update set paid_until=excluded.paid_until;end if;
 update public.stores set employees=(select count(*) from public.store_employees where store_id=s.id and paid_until>v_at) where id=s.id;
 if v_xp>0 then perform public.grant_store_xp(s.id,'business:'||p_kind||':'||case when p_kind='warehouse' then w.tier else o.tier end::text,'BUSINESS',v_xp,v_at);end if;
 perform public.sync_store_progression(s.id);select * into s from public.stores where id=s.id;
 v_result:=jsonb_build_object('kind',p_kind,'code',p_code,'cost_kurus',v_cost::text,'balance_after_kurus',s.cash_kurus::text,'xp_reward',v_xp,'xp_after',s.xp::text,'level_after',s.level,'warehouse_capacity',s.warehouse_capacity,'office_tier',s.office_tier,'brand_value',s.brand_value,'ends_at',v_until);
 insert into public.business_receipts(store_id,request_id,kind,code,expected_tier,result) values(s.id,p_request_id,p_kind,p_code,p_expected_tier,v_result);return v_result;
end;$$;
revoke all on function public.business_action(text,text,integer,uuid) from public,anon,authenticated;
grant execute on function public.business_action(text,text,integer,uuid) to authenticated;

create or replace function public.my_business()
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.stores;v_at timestamptz;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000';end if;
 select * into s from public.stores where user_id=auth.uid() for update;if not found then raise exception 'Store required' using errcode='W0001';end if;
 perform public.sync_store_progression(s.id);v_at:=clock_timestamp();
 update public.stores set employees=(select count(*) from public.store_employees where store_id=s.id and paid_until>v_at) where id=s.id returning * into s;
 return jsonb_build_object('as_of',v_at,'level',s.level,'cash_kurus',s.cash_kurus::text,'warehouse_tier',s.warehouse_tier,'warehouse_capacity',s.warehouse_capacity,'office_tier',s.office_tier,'brand_value',s.brand_value,'business_assets_kurus',s.business_assets_kurus::text,'employees',s.employees,'employee_slots',(select employee_slots from public.business_offices where tier=s.office_tier),'effects',public.business_effects(s.id,v_at),
 'warehouses',(select jsonb_agg(jsonb_build_object('tier',tier,'label',label,'capacity',capacity,'cost_kurus',cost_kurus::text,'min_level',min_level,'xp',xp) order by tier) from public.business_warehouses),
 'offices',(select jsonb_agg(jsonb_build_object('tier',tier,'label',label,'employee_slots',employee_slots,'cost_kurus',cost_kurus::text,'min_level',min_level,'brand_bonus',brand_bonus,'xp',xp) order by tier) from public.business_offices),
 'campaigns',(select jsonb_agg(jsonb_build_object('code',code,'label',label,'cost_kurus',cost_kurus::text,'minutes',minutes,'traffic_bps',traffic_bps,'conversion_bps',conversion_bps,'brand_bonus',brand_bonus) order by cost_kurus) from public.business_ads),
 'active_campaign',(select jsonb_build_object('label',a.label,'ends_at',c.ends_at) from public.store_campaigns c join public.business_ads a on a.code=c.code where c.store_id=s.id and c.ends_at>v_at order by c.starts_at desc limit 1),
 'roles',(select jsonb_agg(jsonb_build_object('code',r.code,'label',r.label,'salary_kurus',r.salary_kurus::text,'level',1,'skill',r.skill,'conversion_bps',r.conversion_bps,'paid_until',e.paid_until,'active',coalesce(e.paid_until>v_at,false)) order by r.code) from public.business_roles r left join public.store_employees e on e.store_id=s.id and e.code=r.code),
 'receipts',(select coalesce(jsonb_agg(jsonb_build_object('result',r.result,'created_at',r.created_at) order by r.created_at desc),'[]'::jsonb) from (select * from public.business_receipts where store_id=s.id order by created_at desc,request_id limit 20) r));
end;$$;
revoke all on function public.my_business() from public,anon,authenticated;grant execute on function public.my_business() to authenticated;
create or replace function public.process_npc_sales()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_store public.stores; v_row record; v_probability numeric; v_sold integer:=0; v_revenue numeric:=0; v_cost numeric:=0; v_balance bigint; v_effects jsonb; v_at timestamptz;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
 select * into v_store from public.stores where user_id=auth.uid() for update;
 if not found then raise exception 'Store not found' using errcode='P0002'; end if;
 v_at:=clock_timestamp();v_effects:=public.business_effects(v_store.id,v_at);
 if v_store.last_npc_tick_at is null or v_at-v_store.last_npc_tick_at>interval '120 seconds' then
  update public.stores set last_npc_tick_at=v_at where id=v_store.id;
  return jsonb_build_object('sold',0,'revenue_kurus','0','profit_kurus','0','wait_seconds',60);
 end if;
 if v_at-v_store.last_npc_tick_at<interval '60 seconds' then
  return jsonb_build_object('sold',0,'revenue_kurus','0','profit_kurus','0','wait_seconds',ceil(extract(epoch from v_store.last_npc_tick_at+interval '60 seconds'-v_at)));
 end if;
 update public.stores set last_npc_tick_at=v_at where id=v_store.id;
 for v_row in select l.product_id,l.price_kurus,i.quantity-i.reserved_quantity as quantity,i.average_cost_kurus,p.market_price_kurus,p.demand
 from public.npc_listings l join public.inventory i on i.store_id=l.store_id and i.product_id=l.product_id join public.products p on p.id=l.product_id
 where l.store_id=v_store.id and l.enabled and i.quantity>i.reserved_quantity order by l.product_id loop
  v_probability:=public.business_npc_probability(v_row.demand,v_row.market_price_kurus,v_row.price_kurus,v_store.reputation,v_effects);
  if random()<v_probability and v_store.cash_kurus<=9000000000000000-v_row.price_kurus then
   update public.inventory set quantity=quantity-1,updated_at=v_at where store_id=v_store.id and product_id=v_row.product_id;
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

-- Preserve existing sales profit and additionally expose operating costs/net profit.
do $$begin if to_regprocedure('public.my_dashboard_phase7()') is null then alter function public.my_dashboard() rename to my_dashboard_phase7;end if;end;$$;
revoke all on function public.my_dashboard_phase7() from public,anon,authenticated;
create or replace function public.my_dashboard()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_data jsonb;v_store uuid;v_cost numeric;v_day timestamptz:=date_trunc('day',now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
begin
 v_data:=public.my_dashboard_phase7();select id into v_store from public.stores where user_id=auth.uid();
 select coalesce(sum(case when type in('WAREHOUSE_UPGRADE','OFFICE_UPGRADE') then -amount_kurus/2 else -amount_kurus end),0) into v_cost from public.transactions where store_id=v_store and type in('WAREHOUSE_UPGRADE','OFFICE_UPGRADE','ADVERTISEMENT','SALARY') and created_at>=v_day and created_at<=now();
 return v_data||jsonb_build_object('operating_costs_kurus',v_cost::text,'net_profit_kurus',case when v_data->>'profit_kurus' is null then null else ((v_data->>'profit_kurus')::numeric-v_cost)::text end);
end;$$;
revoke all on function public.my_dashboard() from public,anon,authenticated;grant execute on function public.my_dashboard() to authenticated;
commit;
