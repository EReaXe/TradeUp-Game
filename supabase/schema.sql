-- Reference component; canonical install is migrations/002_database_core.sql
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
