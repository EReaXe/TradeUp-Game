-- Reference component; canonical install is migrations/002_database_core.sql
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
