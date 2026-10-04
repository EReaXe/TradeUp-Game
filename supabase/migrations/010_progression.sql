-- Phase 10. Prerequisite 009; no cash/inventory resets.
begin;
create table if not exists public.progression_titles(code text primary key,label text not null);
insert into public.progression_titles values('founder','Founder'),('entrepreneur','Entrepreneur'),('wholesaler','Wholesaler'),('trader','Veteran Trader'),('millionaire','Millionaire'),('billionaire','Billionaire'),('collector','Collector'),('market_shark','Market Shark'),('tech_mogul','Tech Mogul'),('daily_trader','Daily Trader') on conflict do nothing;
alter table public.profiles add column if not exists active_title_code text references public.progression_titles(code);
create table if not exists public.progression_achievements (
 code text primary key,label text not null,description text not null,metric text not null,target bigint not null check(target>0),
 xp_reward integer not null check(xp_reward between 1 and 10000),title_code text references public.progression_titles(code)
);
insert into public.progression_achievements values
 ('first_sale','İlk satış','İlk kaydedilen satışını tamamla.','sales_orders',1,50,'founder'),
 ('orders_100','100 sipariş','100 satış işlemini tamamla.','sales_orders',100,250,'trader'),
 ('entrepreneur','Girişimci','10 kârlı NPC satışını tamamla.','profitable_orders',10,100,'entrepreneur'),
 ('wholesaler','Toptancı','Toptan pazar ve fırsatlardan toplam 50 ürün al.','wholesale_units',50,100,'wholesaler'),
 ('millionaire','Milyoner','Net değerin 1.000.000 ₺ olsun.','networth_kurus',100000000,1000,'millionaire'),
 ('billionaire','Milyarder','Net değerin 1.000.000.000 ₺ olsun.','networth_kurus',100000000000,5000,'billionaire'),
 ('collector','Koleksiyoncu','Aynı anda 5 farklı Rare/Epic/Legendary ürün sahibi ol.','rare_owned',5,200,'collector'),
 ('market_shark','Piyasa uzmanı','En az 5 ₺ komisyonlu 5 Marketplace alım veya satımı tamamla.','market_trades',5,100,'market_shark'),
 ('tech_mogul','Teknoloji devi','NPC müşterilere 100 teknoloji ürünü sat.','tech_units',100,500,'tech_mogul') on conflict do nothing;
create table if not exists public.progression_missions (
 code text primary key,label text not null,frequency text not null check(frequency in ('daily','weekly')),metric text not null,
 target bigint not null check(target>0),xp_reward integer not null check(xp_reward between 1 and 10000),
 cash_reward_kurus bigint not null check(cash_reward_kurus between 0 and 1000000),title_code text references public.progression_titles(code)
);
insert into public.progression_missions values
 ('daily_buy','Günlük tedarik','daily','wholesale_units',10,100,2500,null),
 ('daily_sell','Günlük satış','daily','npc_units',25,200,5000,'daily_trader'),
 ('daily_revenue','Günlük ciro','daily','npc_revenue',5000000,300,10000,null),
 ('daily_market','Günlük oyuncu ticareti','daily','market_trades',5,100,0,null),
 ('weekly_buy','Haftalık tedarik','weekly','wholesale_units',50,200,10000,null),
 ('weekly_sell','Haftalık satış','weekly','npc_units',100,500,20000,null),
 ('weekly_market','Haftalık oyuncu ticareti','weekly','market_trades',20,300,0,null) on conflict do nothing;
create table if not exists public.store_achievements(store_id uuid not null references public.stores(id),code text not null references public.progression_achievements(code),unlocked_at timestamptz not null default now(),primary key(store_id,code));
create table if not exists public.store_titles(store_id uuid not null references public.stores(id),code text not null references public.progression_titles(code),unlocked_at timestamptz not null default now(),primary key(store_id,code));
create table if not exists public.store_xp_events (
 store_id uuid not null references public.stores(id),source text not null check(char_length(source) between 1 and 150),
 kind text not null check(kind in ('SALE','ACHIEVEMENT','MISSION','BUSINESS')),amount integer not null check(amount between 0 and 10000),
 recorded_at timestamptz not null default now(),primary key(store_id,source)
);
create index if not exists store_xp_events_time on public.store_xp_events(store_id,kind,recorded_at);
create index if not exists transactions_progression_time on public.transactions(store_id,created_at,type);
create table if not exists public.mission_claims (
 store_id uuid not null references public.stores(id),mission_code text not null references public.progression_missions(code),period_start date not null,
 xp_reward integer not null check(xp_reward>0),cash_reward_kurus bigint not null check(cash_reward_kurus>=0),
 balance_after_kurus bigint not null,xp_after bigint not null,level_after integer not null,claimed_at timestamptz not null default now(),
 primary key(store_id,mission_code,period_start)
);
do $$declare t text;begin
 foreach t in array array['progression_titles','progression_achievements','progression_missions','store_achievements','store_titles','store_xp_events','mission_claims'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
 foreach t in array array['store_achievements','store_titles','store_xp_events','mission_claims'] loop
  execute format('grant select on public.%I to authenticated',t);
  execute format('drop policy if exists progression_own on public.%I',t);
  execute format('create policy progression_own on public.%I for select to authenticated using(exists(select 1 from public.stores s where s.id=store_id and s.user_id=(select auth.uid())))',t);
  execute format('drop trigger if exists progression_immutable on public.%I',t);
  execute format('create trigger progression_immutable before update or delete on public.%I for each row execute function public.reject_ledger_mutation()',t);
 end loop;
end;$$;
create or replace function public.progression_level(p_xp bigint)
returns integer language sql immutable set search_path='' as $$select least(50,floor(sqrt(greatest(0,p_xp)::numeric/100))::integer+1);$$;
revoke all on function public.progression_level(bigint) from public,anon,authenticated;

-- Private metric authority. p_start/p_end are server-derived period boundaries.
create or replace function public.progression_metrics(p_store uuid,p_start timestamptz default '-infinity',p_end timestamptz default 'infinity')
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
 'sales_orders',(select count(*)::text from public.transactions where store_id=p_store and type in ('NPC_SALE','MARKETPLACE_SALE') and amount_kurus>0 and created_at>=p_start and created_at<p_end),
 'profitable_orders',(select count(*)::text from public.transactions where store_id=p_store and type='NPC_SALE' and amount_kurus>cost_of_goods_kurus and created_at>=p_start and created_at<p_end),
 'npc_units',(select coalesce(sum(sale_quantity),0)::text from public.transactions where store_id=p_store and type='NPC_SALE' and amount_kurus>0 and created_at>=p_start and created_at<p_end),
 'npc_revenue',(select coalesce(sum(amount_kurus),0)::text from public.transactions where store_id=p_store and type='NPC_SALE' and amount_kurus>0 and created_at>=p_start and created_at<p_end),
 'wholesale_units',((select coalesce(sum(quantity),0) from public.wholesale_receipts where store_id=p_store and created_at>=p_start and created_at<p_end)+(select coalesce(sum(quantity),0) from public.market_offer_receipts where store_id=p_store and created_at>=p_start and created_at<p_end))::text,
 'market_trades',(select count(*)::text from public.marketplace_receipts where (buyer_store_id=p_store or seller_store_id=p_store) and fee_kurus>=500 and created_at>=p_start and created_at<p_end),
 'tech_units',(select coalesce(sum(t.sale_quantity),0)::text from public.transactions t join public.products p on p.id=t.reference_id where t.store_id=p_store and t.type='NPC_SALE' and t.amount_kurus>0 and p.category='Technology' and t.created_at>=p_start and t.created_at<p_end),
 'rare_owned',(select count(*)::text from public.inventory i join public.products p on p.id=i.product_id where i.store_id=p_store and i.quantity>0 and p.rarity in ('Rare','Epic','Legendary')),
 'networth_kurus',(select (s.cash_kurus+s.business_assets_kurus::numeric-s.debt_kurus+(select coalesce(sum(i.quantity::numeric*p.market_price_kurus),0) from public.inventory i join public.products p on p.id=i.product_id where i.store_id=p_store))::text from public.stores s where s.id=p_store));
$$;
revoke all on function public.progression_metrics(uuid,timestamptz,timestamptz) from public,anon,authenticated;
create or replace function public.grant_store_xp(p_store uuid,p_source text,p_kind text,p_amount integer,p_time timestamptz default now())
returns void language plpgsql security definer set search_path='' as $$
declare v_xp bigint;
begin
 if p_amount<=0 then return;end if;
 perform id from public.stores where id=p_store for update;
 insert into public.store_xp_events(store_id,source,kind,amount,recorded_at) values(p_store,p_source,p_kind,p_amount,p_time) on conflict do nothing;
 if found then update public.stores set xp=xp+p_amount,level=greatest(level,public.progression_level(xp+p_amount)) where id=p_store returning xp into v_xp;end if;
end;$$;
revoke all on function public.grant_store_xp(uuid,text,text,integer,timestamptz) from public,anon,authenticated;
create or replace function public.sync_store_progression(p_store uuid)
returns void language plpgsql security definer set search_path='' as $$
declare r record;a public.progression_achievements;m jsonb;v_start timestamptz;v_used bigint;v_amount integer;
begin
 perform id from public.stores where id=p_store for update;if not found then return;end if;
 for r in select t.* from public.transactions t where t.store_id=p_store and t.type='NPC_SALE' and t.amount_kurus>t.cost_of_goods_kurus and t.sale_quantity>0
  and not exists(select 1 from public.store_xp_events x where x.store_id=p_store and x.source='sale:'||t.id::text) order by t.created_at,t.id
 loop
  v_start:=date_trunc('day',r.created_at at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  select coalesce(sum(amount),0) into v_used from public.store_xp_events where store_id=p_store and kind='SALE' and recorded_at>=v_start and recorded_at<v_start+interval '1 day';
  v_amount:=least(100,r.sale_quantity::bigint*10,greatest(0,2000-v_used))::integer;
  if v_amount>0 then perform public.grant_store_xp(p_store,'sale:'||r.id::text,'SALE',v_amount,r.created_at);
  else insert into public.store_xp_events values(p_store,'sale:'||r.id::text,'SALE',0,r.created_at) on conflict do nothing;end if;
 end loop;
 m:=public.progression_metrics(p_store);
 for a in select * from public.progression_achievements order by code loop
  if (m->>a.metric)::numeric>=a.target then
   insert into public.store_achievements values(p_store,a.code,now()) on conflict do nothing;
   if found then
    perform public.grant_store_xp(p_store,'achievement:'||a.code,'ACHIEVEMENT',a.xp_reward);
    if a.title_code is not null then insert into public.store_titles values(p_store,a.title_code,now()) on conflict do nothing;end if;
   end if;
  end if;
 end loop;
end;$$;
revoke all on function public.sync_store_progression(uuid) from public,anon,authenticated;
create or replace function public.progression_sale_trigger()
returns trigger language plpgsql security definer set search_path='' as $$begin perform public.sync_store_progression(new.store_id);return new;end;$$;
revoke all on function public.progression_sale_trigger() from public,anon,authenticated;
drop trigger if exists progression_sale on public.transactions;
create trigger progression_sale after insert on public.transactions for each row when(new.type='NPC_SALE') execute function public.progression_sale_trigger();

create or replace function public.claim_progression_mission(p_mission_code text,p_period_start date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.stores;m public.progression_missions;c public.mission_claims;v_date date;v_start timestamptz;v_end timestamptz;v_metrics jsonb;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000';end if;
 if p_mission_code is null or p_period_start is null then raise exception 'Invalid mission' using errcode='G0002';end if;
 select * into s from public.stores where user_id=auth.uid() for update;if not found then raise exception 'Store required' using errcode='W0001';end if;
 perform public.sync_store_progression(s.id);
 select * into c from public.mission_claims where store_id=s.id and mission_code=p_mission_code and period_start=p_period_start;
 if not found then
  select * into m from public.progression_missions where code=p_mission_code;if not found then raise exception 'Mission unavailable' using errcode='G0002';end if;
  v_date:=case when m.frequency='daily' then (clock_timestamp() at time zone 'Europe/Istanbul')::date else date_trunc('week',clock_timestamp() at time zone 'Europe/Istanbul')::date end;
  if v_date<>p_period_start then raise exception 'Mission period expired' using errcode='G0004';end if;
  v_start:=v_date::timestamp at time zone 'Europe/Istanbul';v_end:=(v_date+case when m.frequency='daily' then 1 else 7 end)::timestamp at time zone 'Europe/Istanbul';
  v_metrics:=public.progression_metrics(s.id,v_start,v_end);
  if coalesce((v_metrics->>m.metric)::numeric,0)<m.target then raise exception 'Mission incomplete' using errcode='G0003';end if;
  select * into s from public.stores where id=s.id;
  if s.cash_kurus>9000000000000000-m.cash_reward_kurus then raise exception 'Balance limit' using errcode='G0006';end if;
  if m.cash_reward_kurus>0 then
   update public.stores set cash_kurus=cash_kurus+m.cash_reward_kurus where id=s.id returning * into s;
   insert into public.transactions(user_id,store_id,type,amount_kurus,balance_after_kurus,idempotency_key)
    values(s.user_id,s.id,'REWARD',m.cash_reward_kurus,s.cash_kurus,'mission:'||m.code||':'||v_date::text);
  end if;
  perform public.grant_store_xp(s.id,'mission:'||m.code||':'||v_date::text,'MISSION',m.xp_reward);
  if m.title_code is not null then insert into public.store_titles values(s.id,m.title_code,now()) on conflict do nothing;end if;
  select * into s from public.stores where id=s.id;
  insert into public.mission_claims values(s.id,m.code,v_date,m.xp_reward,m.cash_reward_kurus,s.cash_kurus,s.xp,s.level,now()) returning * into c;
 end if;
 return jsonb_build_object('mission_code',c.mission_code,'period_start',c.period_start,'xp_reward',c.xp_reward,'cash_reward_kurus',c.cash_reward_kurus::text,'balance_after_kurus',c.balance_after_kurus::text,'xp_after',c.xp_after::text,'level_after',c.level_after);
end;$$;
revoke all on function public.claim_progression_mission(text,date) from public,anon,authenticated;
grant execute on function public.claim_progression_mission(text,date) to authenticated;
create or replace function public.set_active_title(p_title_code text)
returns void language plpgsql security definer set search_path='' as $$
declare v_store uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000';end if;
 select id into v_store from public.stores where user_id=auth.uid() for update;if not found then raise exception 'Store required' using errcode='W0001';end if;
 perform public.sync_store_progression(v_store);
 if p_title_code is not null and not exists(select 1 from public.store_titles where store_id=v_store and code=p_title_code) then raise exception 'Title not unlocked' using errcode='G0005';end if;
 update public.profiles set active_title_code=p_title_code where id=auth.uid();
end;$$;
revoke all on function public.set_active_title(text) from public,anon,authenticated;
grant execute on function public.set_active_title(text) to authenticated;

create or replace function public.my_progression()
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.stores;v_day date:=(clock_timestamp() at time zone 'Europe/Istanbul')::date;v_week date:=date_trunc('week',clock_timestamp() at time zone 'Europe/Istanbul')::date;
 v_daily jsonb;v_weekly jsonb;v_all jsonb;v_missions jsonb;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000';end if;
 select * into s from public.stores where user_id=auth.uid();if not found then raise exception 'Store required' using errcode='W0001';end if;
 perform public.sync_store_progression(s.id);select * into s from public.stores where id=s.id;
 v_all:=public.progression_metrics(s.id);
 v_daily:=public.progression_metrics(s.id,v_day::timestamp at time zone 'Europe/Istanbul',(v_day+1)::timestamp at time zone 'Europe/Istanbul');
 v_weekly:=public.progression_metrics(s.id,v_week::timestamp at time zone 'Europe/Istanbul',(v_week+7)::timestamp at time zone 'Europe/Istanbul');
 select coalesce(jsonb_agg(jsonb_build_object('code',m.code,'label',m.label,'frequency',m.frequency,'metric',m.metric,'target',m.target::text,
  'progress',case when m.frequency='daily' then v_daily->>m.metric else v_weekly->>m.metric end,'xp_reward',m.xp_reward,'cash_reward_kurus',m.cash_reward_kurus::text,
  'period_start',case when m.frequency='daily' then v_day else v_week end,'ends_at',(case when m.frequency='daily' then v_day+1 else v_week+7 end)::timestamp at time zone 'Europe/Istanbul',
  'claimed',exists(select 1 from public.mission_claims c where c.store_id=s.id and c.mission_code=m.code and c.period_start=case when m.frequency='daily' then v_day else v_week end),
  'title_reward',(select label from public.progression_titles where code=m.title_code)) order by m.frequency,m.code),'[]'::jsonb) into v_missions from public.progression_missions m;
 return jsonb_build_object('as_of',now(),'username',(select username from public.profiles where id=s.user_id),'store_name',s.store_name,'level',s.level,'xp',s.xp::text,
  'level_start_xp',(100::bigint*(s.level-1)*(s.level-1))::text,'next_level_xp',case when s.level>=50 then null else (100::bigint*s.level*s.level)::text end,
  'active_title_code',(select active_title_code from public.profiles where id=s.user_id),'active_title',(select t.label from public.profiles p join public.progression_titles t on t.code=p.active_title_code where p.id=s.user_id),
  'titles',(select coalesce(jsonb_agg(jsonb_build_object('code',t.code,'label',t.label) order by t.label),'[]'::jsonb) from public.store_titles st join public.progression_titles t on t.code=st.code where st.store_id=s.id),
  'achievements',(select coalesce(jsonb_agg(jsonb_build_object('code',a.code,'label',a.label,'description',a.description,'metric',a.metric,'target',a.target::text,'progress',v_all->>a.metric,'xp_reward',a.xp_reward,'title',(select label from public.progression_titles where code=a.title_code),'unlocked',exists(select 1 from public.store_achievements sa where sa.store_id=s.id and sa.code=a.code)) order by a.code),'[]'::jsonb) from public.progression_achievements a),
  'missions',v_missions,'xp_history',(select coalesce(jsonb_agg(jsonb_build_object('source',x.source,'kind',x.kind,'amount',x.amount,'recorded_at',x.recorded_at) order by x.recorded_at desc),'[]'::jsonb) from (select * from public.store_xp_events where store_id=s.id and amount>0 order by recorded_at desc,source limit 20) x));
end;$$;
revoke all on function public.my_progression() from public,anon,authenticated;
grant execute on function public.my_progression() to authenticated;

-- Wrap existing Marketplace implementations without exposing a level bypass.
do $$begin
 if to_regprocedure('public.create_marketplace_listing_phase7(uuid,integer,bigint,uuid)') is null then alter function public.create_marketplace_listing(uuid,integer,bigint,uuid) rename to create_marketplace_listing_phase7;end if;
 if to_regprocedure('public.buy_marketplace_listing_phase7(uuid,integer,bigint,uuid)') is null then alter function public.buy_marketplace_listing(uuid,integer,bigint,uuid) rename to buy_marketplace_listing_phase7;end if;
end;$$;
revoke all on function public.create_marketplace_listing_phase7(uuid,integer,bigint,uuid),public.buy_marketplace_listing_phase7(uuid,integer,bigint,uuid) from public,anon,authenticated;
create or replace function public.create_marketplace_listing(p_product_id uuid,p_quantity integer,p_price_kurus bigint,p_request_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare s public.stores;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000';end if;
 select * into s from public.stores where user_id=auth.uid() for update;if not found then raise exception 'Store required' using errcode='W0001';end if;
 if not exists(select 1 from public.marketplace_listings where seller_store_id=s.id and request_id=p_request_id) then
  perform public.sync_store_progression(s.id);if (select level from public.stores where id=s.id)<5 then raise exception 'Marketplace requires level 5' using errcode='G0001';end if;
 end if;
 return public.create_marketplace_listing_phase7(p_product_id,p_quantity,p_price_kurus,p_request_id);
end;$$;
create or replace function public.buy_marketplace_listing(p_listing_id uuid,p_quantity integer,p_expected_price_kurus bigint,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_buyer uuid;v_seller uuid;v_result jsonb;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000';end if;
 select id into v_buyer from public.stores where user_id=auth.uid();select seller_store_id into v_seller from public.marketplace_listings where id=p_listing_id;
 if v_buyer is null then raise exception 'Store required' using errcode='W0001';end if;
 if v_seller is null then raise exception 'Listing unavailable' using errcode='M0005';end if;
 -- Preserve two-store UUID ordering; never lock the buyer alone first.
 perform id from public.stores where id in(v_buyer,v_seller) order by id for update;
 if not exists(select 1 from public.marketplace_receipts where buyer_store_id=v_buyer and request_id=p_request_id) then
  perform public.sync_store_progression(v_buyer);if (select level from public.stores where id=v_buyer)<5 then raise exception 'Marketplace requires level 5' using errcode='G0001';end if;
 end if;
 v_result:=public.buy_marketplace_listing_phase7(p_listing_id,p_quantity,p_expected_price_kurus,p_request_id);
 perform public.sync_store_progression(v_buyer);perform public.sync_store_progression(v_seller);
 return v_result;
end;$$;
revoke all on function public.create_marketplace_listing(uuid,integer,bigint,uuid),public.buy_marketplace_listing(uuid,integer,bigint,uuid) from public,anon,authenticated;
grant execute on function public.create_marketplace_listing(uuid,integer,bigint,uuid),public.buy_marketplace_listing(uuid,integer,bigint,uuid) to authenticated;
commit;
