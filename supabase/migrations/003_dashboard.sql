-- Phase 3: read-only snapshot. Prerequisite: migration 002.
begin;
create or replace function public.my_dashboard()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 v_user uuid := auth.uid();
 v_store public.stores;
 v_day timestamptz := date_trunc('day',now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
 v_revenue numeric;
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
 -- No sold-goods cost exists in Phase 2. Never equate revenue with profit.
 'profit_kurus',case when v_orders=0 then '0' else null end,
 'inventory_units',v_units::text,'inventory_value_kurus',v_value::text,'inventory_cost_kurus',v_cost::text,
 'warehouse_capacity',v_store.warehouse_capacity,'level',v_store.level,'reputation',v_store.reputation,
 'activity',v_activity,'history',v_history);
end;
$$;
revoke all on function public.my_dashboard() from public,anon,authenticated;
grant execute on function public.my_dashboard() to authenticated;
commit;
