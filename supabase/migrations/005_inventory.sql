-- Phase 5: read-only inventory snapshot, including inactive owned products.
begin;
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
 'quantity',i.quantity,'average_cost_kurus',i.average_cost_kurus::text,'market_price_kurus',p.market_price_kurus::text,
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
