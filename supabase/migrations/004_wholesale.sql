-- Phase 4. Prerequisites: 001-003. All prices are integer kurus.
begin;
create table if not exists public.wholesale_receipts (
 store_id uuid not null references public.stores(id),
 request_id uuid not null,
 product_id uuid not null references public.products(id),
 quantity integer not null check(quantity between 1 and 1000),
 unit_price_kurus bigint not null check(unit_price_kurus>0),
 total_kurus bigint not null check(total_kurus>0),
 balance_after_kurus bigint not null check(balance_after_kurus>=0),
 transaction_id uuid not null unique references public.transactions(id),
 created_at timestamptz not null default now(),
 primary key(store_id,request_id)
);
alter table public.wholesale_receipts enable row level security;
revoke all on public.wholesale_receipts from public,anon,authenticated;
grant select on public.wholesale_receipts to authenticated;
drop policy if exists wholesale_receipts_read_own on public.wholesale_receipts;
create policy wholesale_receipts_read_own on public.wholesale_receipts for select to authenticated
using (exists(select 1 from public.stores s where s.id=wholesale_receipts.store_id and s.user_id=(select auth.uid())));
drop trigger if exists wholesale_receipts_immutable on public.wholesale_receipts;
create trigger wholesale_receipts_immutable before update or delete on public.wholesale_receipts for each row execute function public.reject_ledger_mutation();
create or replace function public.wholesale_catalog()
returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
 'id',id,'name',name,'category',category,'rarity',rarity,
 'wholesale_price_kurus',wholesale_price_kurus::text,'market_price_kurus',market_price_kurus::text,
 'system_stock',system_stock,'demand',demand,'quality',quality
 ) order by category,name),'[]'::jsonb) from public.products where active;
$$;
revoke all on function public.wholesale_catalog() from public,anon,authenticated;
grant execute on function public.wholesale_catalog() to authenticated;
create or replace function public.buy_wholesale(p_product_id uuid,p_quantity integer,p_expected_price_kurus bigint,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid := auth.uid();
 v_store public.stores;
 v_product public.products;
 v_receipt public.wholesale_receipts;
 v_inventory public.inventory;
 v_units bigint;
 v_total bigint;
 v_balance bigint;
 v_transaction uuid;
 v_average bigint;
begin
 if v_user is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if p_quantity is null or p_quantity not between 1 and 1000 or p_product_id is null or p_request_id is null or p_expected_price_kurus is null or p_expected_price_kurus<=0
 then raise exception 'Invalid quantity or request' using errcode='W0003'; end if;
 -- All operations affecting a store must lock its row before any product rows.
 select * into v_store from public.stores where user_id=v_user for update;
 if not found then raise exception 'Store not found' using errcode='W0001'; end if;
 select * into v_receipt from public.wholesale_receipts where store_id=v_store.id and request_id=p_request_id;
 if found then
  if v_receipt.product_id<>p_product_id or v_receipt.quantity<>p_quantity or v_receipt.unit_price_kurus<>p_expected_price_kurus
  then raise exception 'Idempotency key payload mismatch' using errcode='W0008'; end if;
 else
  select * into v_product from public.products where id=p_product_id for update;
  if not found or not v_product.active then raise exception 'Product unavailable' using errcode='W0002'; end if;
  if v_product.wholesale_price_kurus<>p_expected_price_kurus then raise exception 'Price changed' using errcode='W0007'; end if;
  if v_product.system_stock<p_quantity then raise exception 'Insufficient supplier stock' using errcode='W0004'; end if;
  v_total := v_product.wholesale_price_kurus*p_quantity::bigint;
  if v_store.cash_kurus<v_total then raise exception 'Insufficient balance' using errcode='W0005'; end if;
  select coalesce(sum(quantity),0) into v_units from public.inventory where store_id=v_store.id;
  if v_units+p_quantity>v_store.warehouse_capacity then raise exception 'Warehouse capacity exceeded' using errcode='W0006'; end if;
  select * into v_inventory from public.inventory where store_id=v_store.id and product_id=p_product_id;
  v_average := round((coalesce(v_inventory.quantity,0)::numeric*coalesce(v_inventory.average_cost_kurus,0)+v_total)/(coalesce(v_inventory.quantity,0)+p_quantity))::bigint;
  update public.stores set cash_kurus=cash_kurus-v_total where id=v_store.id returning cash_kurus into v_balance;
  update public.products set system_stock=system_stock-p_quantity where id=p_product_id;
  insert into public.inventory(store_id,product_id,quantity,average_cost_kurus)
  values(v_store.id,p_product_id,p_quantity,v_average)
  on conflict(store_id,product_id) do update set quantity=inventory.quantity+excluded.quantity,average_cost_kurus=excluded.average_cost_kurus,updated_at=now();
  insert into public.transactions(user_id,store_id,type,amount_kurus,balance_after_kurus,reference_id,idempotency_key)
  values(v_user,v_store.id,'WHOLESALE_PURCHASE',-v_total,v_balance,p_product_id,'wholesale:'||p_request_id::text) returning id into v_transaction;
  insert into public.wholesale_receipts(store_id,request_id,product_id,quantity,unit_price_kurus,total_kurus,balance_after_kurus,transaction_id)
  values(v_store.id,p_request_id,p_product_id,p_quantity,v_product.wholesale_price_kurus,v_total,v_balance,v_transaction) returning * into v_receipt;
 end if;
 return jsonb_build_object('request_id',v_receipt.request_id,'product_id',v_receipt.product_id,'quantity',v_receipt.quantity,
 'unit_price_kurus',v_receipt.unit_price_kurus::text,'total_kurus',v_receipt.total_kurus::text,
 'balance_after_kurus',v_receipt.balance_after_kurus::text,'transaction_id',v_receipt.transaction_id);
end;
$$;
revoke all on function public.buy_wholesale(uuid,integer,bigint,uuid) from public,anon,authenticated;
grant execute on function public.buy_wholesale(uuid,integer,bigint,uuid) to authenticated;
commit;
