begin;

create or replace function public.current_gold_energy_price()
returns bigint language sql stable security definer set search_path=public as $$
  select greatest(500,least(10000,
    round(1000*(1+ln(1+coalesce(sum(gold),0)::numeric/10000)*0.35))
  ))::bigint
  from public.profiles;
$$;

create or replace function public.current_pack_price(p_key text)
returns bigint language plpgsql stable security definer set search_path=public as $$
declare
  pk public.pack_types;
  catalog_average numeric;
  eligible_average numeric;
  eligible_count numeric;
  available_count numeric;
  value_factor numeric;
  scarcity_factor numeric;
begin
  select * into pk from public.pack_types where key=p_key and is_active;
  if not found then raise exception 'PACK_NOT_FOUND'; end if;
  if pk.daily or pk.cost=0 then return 0; end if;

  select avg(greatest(score,1)) into catalog_average
  from public.cards where is_active and drop_weight>0;

  select
    sum(greatest(c.score,1)*c.drop_weight)/nullif(sum(c.drop_weight),0),
    count(*),
    count(*) filter(where
      c.max_supply is null or c.minted_supply<c.max_supply or
      exists(select 1 from public.system_card_pool sp where sp.card_id=c.id and sp.claimed_at is null)
    )
  into eligible_average,eligible_count,available_count
  from public.cards c
  where c.is_active and c.drop_weight>0
    and (c.drop_starts_at is null or c.drop_starts_at<=now())
    and (c.drop_ends_at is null or c.drop_ends_at>now())
    and (pk.rarity_floor is null or c.rarity>=pk.rarity_floor);

  value_factor:=greatest(0.65,least(2.50,
    sqrt(coalesce(eligible_average/nullif(catalog_average,0),1))
  ));
  scarcity_factor:=greatest(1,least(1.50,
    1+(1-coalesce(available_count/nullif(eligible_count,0),1))*0.50
  ));

  return greatest(1,round(pk.cost*value_factor*scarcity_factor))::bigint;
end
$$;

create or replace function public.get_economy_rates()
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'gold_energy_price',public.current_gold_energy_price(),
    'total_player_gold',(select coalesce(sum(gold),0) from public.profiles),
    'pack_prices',(select coalesce(jsonb_object_agg(key,public.current_pack_price(key)),'{}'::jsonb)
                   from public.pack_types where is_active)
  );
$$;

create or replace function public.open_pack(p_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 uid uuid:=auth.uid();pk public.pack_types;chosen public.cards;pool public.system_card_pool;
 total numeric;target numeric;rec record;serial integer;copy_id uuid;p public.profiles;
 recycled boolean:=false;dynamic_cost bigint;
begin
 if uid is null then raise exception 'AUTH_REQUIRED';end if;
 perform public.enforce_rate_limit('open_pack',15,60);
 perform public.sync_energy();
 select * into pk from public.pack_types where key=p_key and is_active for share;
 if not found then raise exception 'PACK_NOT_FOUND';end if;
 dynamic_cost:=public.current_pack_price(p_key);
 if pk.daily then
  if exists(select 1 from public.daily_claims where owner_id=uid and pack_key=p_key and created_at>now()-interval '24 hours')then raise exception 'DAILY_ALREADY_CLAIMED';end if;
  insert into public.daily_claims(owner_id,pack_key)values(uid,p_key)on conflict do nothing;
  if not found then raise exception 'DAILY_ALREADY_CLAIMED';end if;
 else
  update public.profiles set energy=energy-dynamic_cost,updated_at=now()
  where id=uid and energy>=dynamic_cost returning * into p;
  if not found then raise exception 'NOT_ENOUGH_ENERGY';end if;
 end if;
 select sum(drop_weight)into total from public.cards c where c.is_active and c.drop_weight>0
  and(c.drop_starts_at is null or c.drop_starts_at<=now())and(c.drop_ends_at is null or c.drop_ends_at>now())
  and(c.max_supply is null or c.minted_supply<c.max_supply or exists(select 1 from public.system_card_pool sp where sp.card_id=c.id and sp.claimed_at is null))
  and(pk.rarity_floor is null or c.rarity>=pk.rarity_floor);
 if coalesce(total,0)<=0 then raise exception 'NO_AVAILABLE_CARDS';end if;
 target:=random()*total;
 for rec in select c.* from public.cards c where c.is_active and c.drop_weight>0
  and(c.drop_starts_at is null or c.drop_starts_at<=now())and(c.drop_ends_at is null or c.drop_ends_at>now())
  and(c.max_supply is null or c.minted_supply<c.max_supply or exists(select 1 from public.system_card_pool sp where sp.card_id=c.id and sp.claimed_at is null))
  and(pk.rarity_floor is null or c.rarity>=pk.rarity_floor)order by c.id for update
 loop target:=target-rec.drop_weight;if target<=0 then chosen:=rec;exit;end if;end loop;
 if chosen.id is null then raise exception 'CARD_SELECTION_FAILED';end if;
 select * into pool from public.system_card_pool where card_id=chosen.id and claimed_at is null order by returned_at,id limit 1 for update skip locked;
 if found then
  recycled:=true;serial:=pool.serial_number;
  insert into public.player_cards(owner_id,card_id,serial_number,variant,condition,obtained_from)
  values(uid,chosen.id,pool.serial_number,pool.variant,pool.condition,'recycled_pack')returning id into copy_id;
  update public.system_card_pool set claimed_at=now(),claimed_by=uid,replacement_player_card_id=copy_id where id=pool.id;
 elsif chosen.max_supply is not null then
  update public.cards set minted_supply=minted_supply+1,updated_at=now()where id=chosen.id and minted_supply<max_supply returning minted_supply into serial;
  if not found then raise exception 'CARD_SOLD_OUT';end if;
  insert into public.player_cards(owner_id,card_id,serial_number,obtained_from)values(uid,chosen.id,serial,p_key)returning id into copy_id;
 else
  insert into public.player_cards(owner_id,card_id,serial_number,obtained_from)values(uid,chosen.id,null,p_key)returning id into copy_id;
 end if;
 select * into p from public.profiles where id=uid;
 return jsonb_build_object('card',to_jsonb(chosen),'player_card_id',copy_id,'serial_number',serial,'recycled',recycled,'price_paid',dynamic_cost,'profile',to_jsonb(p));
end $$;

create or replace function public.get_pack_status()
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object(
  'next_daily_at',(select max(dc.created_at)+interval '24 hours' from public.daily_claims dc where dc.owner_id=auth.uid()),
  'available_card_count',(select count(*) from public.cards c where c.is_active and c.drop_weight>0
   and(c.drop_starts_at is null or c.drop_starts_at<=now())and(c.drop_ends_at is null or c.drop_ends_at>now())
   and(c.max_supply is null or c.minted_supply<c.max_supply or exists(select 1 from public.system_card_pool sp where sp.card_id=c.id and sp.claimed_at is null))),
  'pack_availability',(select coalesce(jsonb_object_agg(pk.key,(select count(*) from public.cards c where c.is_active and c.drop_weight>0
   and(c.drop_starts_at is null or c.drop_starts_at<=now())and(c.drop_ends_at is null or c.drop_ends_at>now())
   and(c.max_supply is null or c.minted_supply<c.max_supply or exists(select 1 from public.system_card_pool sp where sp.card_id=c.id and sp.claimed_at is null))
   and(pk.rarity_floor is null or c.rarity>=pk.rarity_floor))),'{}'::jsonb)from public.pack_types pk where pk.is_active),
  'pack_prices',(select coalesce(jsonb_object_agg(pk.key,public.current_pack_price(pk.key)),'{}'::jsonb)from public.pack_types pk where pk.is_active),
  'gold_energy_price',public.current_gold_energy_price(),
  'total_player_gold',(select coalesce(sum(gold),0)from public.profiles)
 );
$$;

create or replace function public.convert_energy_to_gold(p_gold integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid();needed bigint;p public.profiles;unit_price bigint;
begin
 if uid is null then raise exception 'AUTH_REQUIRED';end if;
 perform public.enforce_rate_limit('convert_gold',12,60);
 if p_gold is null or p_gold<1 or p_gold>100000 then raise exception 'INVALID_GOLD_AMOUNT';end if;
 perform public.sync_energy();
 perform 1 from public.profiles order by id for update;
 unit_price:=public.current_gold_energy_price();
 needed:=p_gold::bigint*unit_price;
 update public.profiles set energy=energy-needed,gold=gold+p_gold,updated_at=now()
 where id=uid and energy>=needed returning * into p;
 if not found then raise exception 'NOT_ENOUGH_ENERGY';end if;
 insert into public.gold_ledger(owner_id,amount,balance_after,reason)
 values(uid,p_gold,p.gold,'energy_conversion');
 return jsonb_build_object('profile',to_jsonb(p),'gold_received',p_gold,'energy_spent',needed,'unit_price',unit_price);
end $$;

revoke all on function public.current_gold_energy_price(),public.current_pack_price(text),public.get_economy_rates() from public,anon;
grant execute on function public.current_gold_energy_price(),public.current_pack_price(text),public.get_economy_rates() to authenticated;

commit;
