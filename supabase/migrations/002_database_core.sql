-- Prerequisite: 001_store_onboarding.sql. No table drops or data resets.
begin;
-- Phase 2: monetary amounts are integer kurus, never floating point.
create table if not exists public.profiles (
 id uuid primary key references auth.users(id),
 username text not null check (username ~ '^[a-zA-Z0-9_]{3,24}$'),
 created_at timestamptz not null default now()
);
create unique index if not exists profiles_username_unique on public.profiles(lower(username));
create table if not exists public.stores (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null unique references public.profiles(id),
 store_name text not null check (char_length(store_name) between 3 and 40 and store_name=btrim(store_name)),
 cash_kurus bigint not null default 1000000 check(cash_kurus between 0 and 9000000000000000),
 level integer not null default 1 check(level between 1 and 1000),
 xp bigint not null default 0 check(xp>=0),
 reputation integer not null default 0 check(reputation between 0 and 100),
 warehouse_capacity integer not null default 50 check(warehouse_capacity between 1 and 1000000),
 listing_limit integer not null default 5 check(listing_limit between 1 and 10000),
 employees integer not null default 0 check(employees between 0 and 10000),
 business_assets_kurus bigint not null default 0 check(business_assets_kurus between 0 and 9000000000000000),
 debt_kurus bigint not null default 0 check(debt_kurus between 0 and 9000000000000000),
 created_at timestamptz not null default now()
);
create unique index if not exists stores_id_owner_unique on public.stores(id,user_id);
create unique index if not exists stores_name_unique on public.stores(lower(store_name));
create table if not exists public.products (
 id uuid primary key,
 name text not null check(char_length(name) between 1 and 100),
 category text not null check(category in ('Technology','Gaming','Clothing','Cosmetics','Sports','Stationery','Home','Collectibles')),
 subcategory text not null,
 base_price_kurus bigint not null check(base_price_kurus between 1 and 1000000000000),
 wholesale_price_kurus bigint not null check(wholesale_price_kurus between 1 and 1000000000000),
 market_price_kurus bigint not null check(market_price_kurus between 1 and 1000000000000),
 rarity text not null check(rarity in ('Common','Uncommon','Rare','Epic','Legendary')),
 quality integer not null check(quality between 1 and 100),
 demand integer not null check(demand between 0 and 100),
 supply integer not null check(supply between 0 and 100),
 system_stock integer not null check(system_stock between 0 and 1000000),
 image text,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create index if not exists products_category_active on public.products(category,active);
create table if not exists public.inventory (
 store_id uuid not null references public.stores(id),
 product_id uuid not null references public.products(id),
 quantity integer not null check(quantity between 0 and 1000000),
 average_cost_kurus bigint not null check(average_cost_kurus between 0 and 1000000000000),
 updated_at timestamptz not null default now(),
 primary key(store_id,product_id)
);
-- Each future money operation must include its ledger entry in the same transaction.
create table if not exists public.transactions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id),
 store_id uuid not null references public.stores(id),
 type text not null check(type in ('INITIAL_CAPITAL','WHOLESALE_PURCHASE','MARKETPLACE_PURCHASE','MARKETPLACE_SALE','NPC_SALE','MARKETPLACE_FEE','WAREHOUSE_UPGRADE','ADVERTISEMENT','SALARY','LOAN','LOAN_PAYMENT','REWARD')),
 amount_kurus bigint not null check(amount_kurus between -9000000000000000 and 9000000000000000 and amount_kurus<>0),
 balance_after_kurus bigint not null check(balance_after_kurus between 0 and 9000000000000000),
 reference_id uuid,
 idempotency_key text not null check(char_length(idempotency_key) between 1 and 150),
 created_at timestamptz not null default now(),
 unique(store_id,idempotency_key),
 foreign key(store_id,user_id) references public.stores(id,user_id)
);
create index if not exists transactions_owner_date on public.transactions(user_id,created_at desc);
alter table public.profiles enable row level security;
alter table public.stores enable row level security;
alter table public.products enable row level security;
alter table public.inventory enable row level security;
alter table public.transactions enable row level security;
revoke all on public.profiles,public.stores,public.products,public.inventory,public.transactions from public,anon,authenticated;
grant select on public.profiles,public.stores,public.products,public.inventory,public.transactions to authenticated;
drop policy if exists profiles_read_own on public.profiles;
create policy profiles_read_own on public.profiles for select to authenticated using (id=(select auth.uid()));
drop policy if exists stores_read_own on public.stores;
create policy stores_read_own on public.stores for select to authenticated using (user_id=(select auth.uid()));
drop policy if exists products_read_active on public.products;
create policy products_read_active on public.products for select to authenticated using (active);
drop policy if exists inventory_read_own on public.inventory;
create policy inventory_read_own on public.inventory for select to authenticated using (exists(select 1 from public.stores s where s.id=inventory.store_id and s.user_id=(select auth.uid())));
drop policy if exists transactions_read_own on public.transactions;
create policy transactions_read_own on public.transactions for select to authenticated using (user_id=(select auth.uid()));
-- No client insert/update/delete policies, including profiles and store identity.
create or replace function public.reject_ledger_mutation()
returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Transaction ledger is immutable' using errcode='55000'; end;
$$;
revoke all on function public.reject_ledger_mutation() from public,anon,authenticated;
drop trigger if exists transactions_immutable on public.transactions;
create trigger transactions_immutable before update or delete on public.transactions for each row execute function public.reject_ledger_mutation();
-- Keep Phase 1 RPC return type and endpoint compatible. One atomic identity/core/grant transaction.
create or replace function public.complete_store_onboarding(p_username text,p_store_name text)
returns public.store_onboarding language plpgsql security definer set search_path='' as $$
declare
 v_user uuid := auth.uid();
 v_identity public.store_onboarding;
 v_store public.stores;
 v_created boolean := false;
begin
 if v_user is null then raise exception 'Authentication required' using errcode='28000'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text,0));
 select * into v_identity from public.store_onboarding where user_id=v_user;
 if not found then
  if p_username is null or p_username !~ '^[a-zA-Z0-9_]{3,24}$' or p_store_name is null or char_length(btrim(p_store_name)) not between 3 and 40
  then raise exception 'Invalid store identity' using errcode='22023'; end if;
  insert into public.store_onboarding(user_id,username,store_name)
  values(v_user,p_username,btrim(p_store_name)) returning * into v_identity;
 end if;
 insert into public.profiles(id,username,created_at) values(v_user,v_identity.username,v_identity.created_at)
 on conflict(id) do nothing;
 select * into v_store from public.stores where user_id=v_user;
 if not found then
  insert into public.stores(user_id,store_name,created_at)
  values(v_user,v_identity.store_name,v_identity.created_at) returning * into v_store;
  v_created := true;
 end if;
 if v_created then
  insert into public.transactions(user_id,store_id,type,amount_kurus,balance_after_kurus,idempotency_key)
  values(v_user,v_store.id,'INITIAL_CAPITAL',1000000,v_store.cash_kurus,'initial-capital');
 end if;
 return v_identity;
end;
$$;
revoke all on function public.complete_store_onboarding(text,text) from public,anon,authenticated;
grant execute on function public.complete_store_onboarding(text,text) to authenticated;
-- Definer reads inactive owned inventory too; auth.uid strictly selects only the caller.
-- Derived in SQL, never supplied by the client. numeric aggregate avoids bigint overflow.
create or replace function public.my_net_worth_kurus()
returns numeric language sql stable security definer set search_path='' as $$
 select s.cash_kurus::numeric+s.business_assets_kurus-s.debt_kurus+
 coalesce((select sum(i.quantity::numeric*p.market_price_kurus) from public.inventory i join public.products p on p.id=i.product_id where i.store_id=s.id),0)
 from public.stores s where s.user_id=(select auth.uid());
$$;
revoke all on function public.my_net_worth_kurus() from public,anon,authenticated;
grant execute on function public.my_net_worth_kurus() to authenticated;
-- Preserve Phase 1 identities; reapplying never resets cash or duplicates capital.
insert into public.profiles(id,username,created_at)
select user_id,username,created_at from public.store_onboarding on conflict(id) do nothing;
with new_stores as (
 insert into public.stores(user_id,store_name,created_at)
 select user_id,store_name,created_at from public.store_onboarding
 on conflict(user_id) do nothing returning id,user_id,cash_kurus
)
insert into public.transactions(user_id,store_id,type,amount_kurus,balance_after_kurus,idempotency_key)
select user_id,id,'INITIAL_CAPITAL',1000000,cash_kurus,'initial-capital' from new_stores;

commit;
