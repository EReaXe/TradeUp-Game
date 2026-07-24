begin;

-- Keep the player-card row as an audit/history record. Deleting it can fail when
-- an older market listing, trade, or fusion still references the card copy.
create or replace function public.sell_card_to_system(p_player_card uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  uid uuid:=auth.uid();
  pc public.player_cards;
  c public.cards;
  payout bigint;
  p public.profiles;
begin
  if uid is null then raise exception 'AUTH_REQUIRED'; end if;
  perform public.enforce_rate_limit('system_buyback',20,60);

  select * into pc
  from public.player_cards
  where id=p_player_card and owner_id=uid and retired_at is null
  for update;

  if not found then raise exception 'CARD_COPY_NOT_FOUND'; end if;
  if exists(select 1 from public.trade_reserved_cards where player_card_id=pc.id) then
    raise exception 'CARD_RESERVED_FOR_TRADE';
  end if;
  if exists(select 1 from public.market_listings where player_card_id=pc.id and status='active') then
    raise exception 'CARD_LISTED';
  end if;

  select * into c from public.cards where id=pc.card_id;
  payout:=greatest(1,floor(greatest(c.score,1)*0.20));

  insert into public.system_card_pool(
    original_player_card_id,card_id,serial_number,variant,condition,returned_by
  )
  values(pc.id,pc.card_id,pc.serial_number,pc.variant,pc.condition,uid);

  update public.player_cards
  set retired_at=now(),retired_reason='system_buyback',updated_at=now()
  where id=pc.id;

  update public.profiles
  set gold=gold+payout,updated_at=now()
  where id=uid
  returning * into p;

  insert into public.gold_ledger(owner_id,amount,balance_after,reason,reference_id)
  values(uid,payout,p.gold,'system_buyback',pc.id);

  return jsonb_build_object(
    'profile',to_jsonb(p),
    'gold_received',payout,
    'card_id',c.id,
    'recycled',true
  );
end
$$;

revoke all on function public.sell_card_to_system(uuid) from public,anon;
grant execute on function public.sell_card_to_system(uuid) to authenticated;

commit;
