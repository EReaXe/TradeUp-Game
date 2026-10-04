-- Reference component; canonical install is migrations/002_database_core.sql
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
