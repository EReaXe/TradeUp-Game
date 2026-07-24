begin;

create or replace function public.buy_market_listing(p_listing uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); l public.market_listings; buyer public.profiles; seller_balance bigint; copy_id uuid; serial integer;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 perform public.enforce_rate_limit('market_purchase',20,60);
 select * into l from public.market_listings where id=p_listing for update;
 if not found or l.status<>'active' or l.listing_type<>'fixed' or (l.ends_at is not null and l.ends_at<=now()) then raise exception 'LISTING_UNAVAILABLE'; end if;
 if l.seller_id=uid then raise exception 'OWN_LISTING'; end if;
 update public.profiles set gold=gold-l.price,updated_at=now() where id=uid and gold>=l.price returning * into buyer;
 if not found then raise exception 'NOT_ENOUGH_GOLD'; end if;
 insert into public.gold_ledger(owner_id,amount,balance_after,reason,reference_id) values(uid,-l.price,buyer.gold,'market_purchase',l.id);
 if l.source_type='player' then
  update public.player_cards set owner_id=uid,obtained_at=now(),obtained_from='market' where id=l.player_card_id and owner_id=l.seller_id returning id into copy_id;
  if not found then raise exception 'CARD_OWNERSHIP_CHANGED'; end if;
  update public.profiles set gold=gold+l.price,updated_at=now() where id=l.seller_id returning gold into seller_balance;
  insert into public.gold_ledger(owner_id,amount,balance_after,reason,reference_id) values(l.seller_id,l.price,seller_balance,'market_sale',l.id);
  insert into public.notifications(owner_id,type,title,body,reference_id,metadata) values(l.seller_id,'card_sold','Kartın satıldı',l.price||' Gold hesabına eklendi.',l.id,jsonb_build_object('card_id',l.card_id,'price',l.price,'buyer_id',uid)) on conflict do nothing;
 else
  update public.cards set minted_supply=minted_supply+1,updated_at=now() where id=l.card_id and (max_supply is null or minted_supply<max_supply)
   returning case when max_supply is null then null else minted_supply end into serial;
  if not found then raise exception 'CARD_SOLD_OUT'; end if;
  insert into public.player_cards(owner_id,card_id,serial_number,obtained_from) values(uid,l.card_id,serial,'system_market') returning id into copy_id;
 end if;
 update public.market_listings set status='sold',sold_at=now(),updated_at=now() where id=l.id;
 return jsonb_build_object('profile',to_jsonb(buyer),'player_card_id',copy_id,'card_id',l.card_id,'price',l.price);
end $$;

create or replace function public.place_auction_bid(p_listing uuid,p_amount bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); l public.market_listings; charge bigint; minimum bigint; bidder public.profiles; refunded_balance bigint;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 perform public.enforce_rate_limit('auction_bid',30,60);
 select * into l from public.market_listings where id=p_listing for update;
 if not found or l.status<>'active' or l.listing_type<>'auction' then raise exception 'AUCTION_UNAVAILABLE'; end if;
 if l.ends_at<=now() then raise exception 'AUCTION_ENDED'; end if;
 if l.seller_id=uid then raise exception 'OWN_LISTING'; end if;
 minimum:=case when l.current_bid is null then l.price else l.current_bid+1 end;
 if p_amount is null or p_amount<minimum then raise exception 'BID_TOO_LOW'; end if;
 charge:=case when l.current_bidder=uid then p_amount-l.current_bid else p_amount end;
 update public.profiles set gold=gold-charge,updated_at=now() where id=uid and gold>=charge returning * into bidder;
 if not found then raise exception 'NOT_ENOUGH_GOLD'; end if;
 insert into public.gold_ledger(owner_id,amount,balance_after,reason,reference_id) values(uid,-charge,bidder.gold,'auction_bid_lock',l.id);
 if l.current_bidder is not null and l.current_bidder<>uid then
  update public.profiles set gold=gold+l.current_bid,updated_at=now() where id=l.current_bidder returning gold into refunded_balance;
  insert into public.gold_ledger(owner_id,amount,balance_after,reason,reference_id) values(l.current_bidder,l.current_bid,refunded_balance,'auction_outbid_refund',l.id);
  insert into public.notifications(owner_id,type,title,body,reference_id,metadata) values(l.current_bidder,'outbid','Teklifin geçildi','Açık artırmada daha yüksek bir teklif verildi.',l.id,jsonb_build_object('listing_id',l.id,'new_bid',p_amount)) on conflict(owner_id,type,reference_id) where reference_id is not null do update set body=excluded.body,metadata=excluded.metadata,read_at=null,created_at=now();
 end if;
 insert into public.market_bids(listing_id,bidder_id,amount) values(l.id,uid,p_amount);
 update public.market_listings set current_bid=p_amount,current_bidder=uid,updated_at=now() where id=l.id;
 return jsonb_build_object('profile',to_jsonb(bidder),'current_bid',p_amount,'ends_at',l.ends_at);
end $$;

create or replace function public.settle_auction(p_listing uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l public.market_listings; payout bigint; seller_balance bigint; copy_id uuid;
begin
 select * into l from public.market_listings where id=p_listing for update;
 if not found then raise exception 'LISTING_NOT_FOUND'; end if;
 if l.status<>'active' then return jsonb_build_object('status',l.status); end if;
 if l.listing_type<>'auction' or l.ends_at>now() then raise exception 'AUCTION_NOT_ENDED'; end if;
 if l.current_bidder is null then
  update public.market_listings set status='expired',updated_at=now() where id=l.id;
  return jsonb_build_object('status','expired');
 end if;
 update public.player_cards set owner_id=l.current_bidder,obtained_at=now(),obtained_from='auction' where id=l.player_card_id and owner_id=l.seller_id returning id into copy_id;
 if not found then raise exception 'CARD_OWNERSHIP_CHANGED'; end if;
 payout:=floor(l.current_bid*(1-l.commission_rate));
 update public.profiles set gold=gold+payout,updated_at=now() where id=l.seller_id returning gold into seller_balance;
 insert into public.gold_ledger(owner_id,amount,balance_after,reason,reference_id) values(l.seller_id,payout,seller_balance,'auction_sale',l.id);
 update public.market_listings set status='sold',sold_at=now(),updated_at=now() where id=l.id;
 insert into public.notifications(owner_id,type,title,body,reference_id,metadata) values
  (l.current_bidder,'auction_won','Açık artırmayı kazandın',l.current_bid||' Gold karşılığında kart koleksiyonuna eklendi.',l.id,jsonb_build_object('card_id',l.card_id,'price',l.current_bid)),
  (l.seller_id,'card_sold','Kartın satıldı',payout||' Gold hesabına eklendi.',l.id,jsonb_build_object('card_id',l.card_id,'price',l.current_bid,'payout',payout))
 on conflict do nothing;
 return jsonb_build_object('status','sold','winner_id',l.current_bidder,'price',l.current_bid,'seller_payout',payout,'player_card_id',copy_id);
end $$;

create or replace function public.settle_expired_auctions()
returns integer language plpgsql security definer set search_path=public as $$
declare rec record; settled integer:=0;
begin
 for rec in select id from public.market_listings where status='active' and listing_type='auction' and ends_at<=now() order by ends_at limit 100
 loop perform public.settle_auction(rec.id); settled:=settled+1; end loop;
 return settled;
end $$;

create or replace function public.sell_card_to_system(p_player_card uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); pc public.player_cards; c public.cards; payout bigint; p public.profiles;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 perform public.enforce_rate_limit('system_buyback',20,60);
 select * into pc from public.player_cards where id=p_player_card and owner_id=uid and retired_at is null for update;
 if not found then raise exception 'CARD_COPY_NOT_FOUND'; end if;
 if exists(select 1 from public.trade_reserved_cards where player_card_id=pc.id) then raise exception 'CARD_RESERVED_FOR_TRADE'; end if;
 if exists(select 1 from public.market_listings where player_card_id=pc.id and status='active') then raise exception 'CARD_LISTED'; end if;
 select * into c from public.cards where id=pc.card_id;
 payout:=greatest(1,floor(greatest(c.score,1)*0.20));
 insert into public.system_card_pool(original_player_card_id,card_id,serial_number,variant,condition,returned_by)
 values(pc.id,pc.card_id,pc.serial_number,pc.variant,pc.condition,uid);
 update public.player_cards
 set retired_at=now(),retired_reason='system_buyback',updated_at=now()
 where id=pc.id;
 update public.profiles set gold=gold+payout,updated_at=now() where id=uid returning * into p;
 insert into public.gold_ledger(owner_id,amount,balance_after,reason,reference_id) values(uid,payout,p.gold,'system_buyback',pc.id);
 return jsonb_build_object('profile',to_jsonb(p),'gold_received',payout,'card_id',c.id,'recycled',true);
end $$;

create or replace function public.create_trade_offer(
 p_recipient uuid,p_offered_cards uuid[] default '{}',p_requested_cards uuid[] default '{}',
 p_offered_gold bigint default 0,p_requested_gold bigint default 0,p_expires_hours integer default 48)
returns uuid language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); v_trade_id uuid; v_card_id uuid;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 perform public.enforce_rate_limit('create_trade',12,60);
 if p_recipient is null or p_recipient=uid or not exists(select 1 from public.profiles where id=p_recipient) then raise exception 'INVALID_TRADE_RECIPIENT'; end if;
 if coalesce(p_offered_gold,0)<0 or coalesce(p_requested_gold,0)<0 then raise exception 'INVALID_GOLD_AMOUNT'; end if;
 if cardinality(coalesce(p_offered_cards,'{}'))+cardinality(coalesce(p_requested_cards,'{}'))=0 and coalesce(p_offered_gold,0)=0 and coalesce(p_requested_gold,0)=0 then raise exception 'EMPTY_TRADE'; end if;
 if p_expires_hours<1 or p_expires_hours>168 then raise exception 'INVALID_TRADE_EXPIRY'; end if;
 if coalesce(p_offered_cards,'{}')&&coalesce(p_requested_cards,'{}') then raise exception 'DUPLICATE_TRADE_CARD'; end if;
 perform 1 from public.profiles where id in(uid,p_recipient) order by id for update;
 if (select gold from public.profiles where id=uid)<coalesce(p_offered_gold,0) then raise exception 'NOT_ENOUGH_GOLD'; end if;
 insert into public.trade_offers(proposer_id,recipient_id,offered_gold,requested_gold,expires_at)
 values(uid,p_recipient,coalesce(p_offered_gold,0),coalesce(p_requested_gold,0),now()+make_interval(hours=>p_expires_hours)) returning id into v_trade_id;
 foreach v_card_id in array coalesce(p_offered_cards,'{}') loop
  perform 1 from public.player_cards pc where pc.id=v_card_id and pc.owner_id=uid and pc.retired_at is null for update;
  if not found then raise exception 'OFFERED_CARD_NOT_OWNED'; end if;
  if exists(select 1 from public.market_listings ml where ml.player_card_id=v_card_id and ml.status='active') then raise exception 'CARD_LISTED'; end if;
  insert into public.trade_offer_items values(v_trade_id,v_card_id,uid,'offered');
  insert into public.trade_reserved_cards values(v_card_id,v_trade_id,uid,now());
 end loop;
 foreach v_card_id in array coalesce(p_requested_cards,'{}') loop
  perform 1 from public.player_cards pc where pc.id=v_card_id and pc.owner_id=p_recipient and pc.retired_at is null for update;
  if not found then raise exception 'REQUESTED_CARD_NOT_OWNED'; end if;
  if exists(select 1 from public.market_listings ml where ml.player_card_id=v_card_id and ml.status='active') then raise exception 'CARD_LISTED'; end if;
  insert into public.trade_offer_items values(v_trade_id,v_card_id,p_recipient,'requested');
  insert into public.trade_reserved_cards values(v_card_id,v_trade_id,p_recipient,now());
 end loop;
 return v_trade_id;
end $$;

create or replace function public.accept_trade_offer(p_trade uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); t public.trade_offers; proposer public.profiles; recipient public.profiles; proposer_delta bigint; recipient_delta bigint;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 perform public.enforce_rate_limit('accept_trade',12,60);
 select * into t from public.trade_offers where id=p_trade for update;
 if not found or t.status<>'pending' then raise exception 'TRADE_UNAVAILABLE'; end if;
 if t.recipient_id<>uid then raise exception 'TRADE_NOT_RECIPIENT'; end if;
 if t.expires_at<=now() then update public.trade_offers set status='expired',updated_at=now() where id=t.id; delete from public.trade_reserved_cards where trade_id=t.id; raise exception 'TRADE_EXPIRED'; end if;
 perform 1 from public.profiles where id in(t.proposer_id,t.recipient_id) order by id for update;
 select * into proposer from public.profiles where id=t.proposer_id;
 select * into recipient from public.profiles where id=t.recipient_id;
 if proposer.gold<t.offered_gold or recipient.gold<t.requested_gold then raise exception 'TRADE_NOT_ENOUGH_GOLD'; end if;
 if exists(select 1 from public.trade_offer_items i left join public.player_cards pc on pc.id=i.player_card_id where i.trade_id=t.id and (pc.id is null or pc.owner_id<>i.owner_id or pc.retired_at is not null)) then raise exception 'TRADE_OWNERSHIP_CHANGED'; end if;
 if exists(select 1 from public.trade_offer_items i left join public.trade_reserved_cards r on r.player_card_id=i.player_card_id and r.trade_id=i.trade_id where i.trade_id=t.id and r.player_card_id is null) then raise exception 'TRADE_RESERVATION_LOST'; end if;
 proposer_delta:=t.requested_gold-t.offered_gold; recipient_delta:=-proposer_delta;
 update public.profiles set gold=gold+proposer_delta,updated_at=now() where id=t.proposer_id returning * into proposer;
 update public.profiles set gold=gold+recipient_delta,updated_at=now() where id=t.recipient_id returning * into recipient;
 if proposer_delta<>0 then insert into public.gold_ledger(owner_id,amount,balance_after,reason,reference_id) values(t.proposer_id,proposer_delta,proposer.gold,'trade',t.id); end if;
 if recipient_delta<>0 then insert into public.gold_ledger(owner_id,amount,balance_after,reason,reference_id) values(t.recipient_id,recipient_delta,recipient.gold,'trade',t.id); end if;
 update public.player_cards pc set owner_id=case when i.side='offered' then t.recipient_id else t.proposer_id end,obtained_from='trade',obtained_at=now(),updated_at=now()
 from public.trade_offer_items i where i.trade_id=t.id and pc.id=i.player_card_id;
 update public.trade_offers set status='accepted',updated_at=now() where id=t.id;
 delete from public.trade_reserved_cards where trade_id=t.id;
 return jsonb_build_object('trade_id',t.id,'status','accepted','profile',to_jsonb(recipient));
end $$;

create or replace function public.close_trade_offer(p_trade uuid,p_action text)
returns boolean language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); t public.trade_offers; next_status text;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into t from public.trade_offers where id=p_trade for update;
 if not found or t.status<>'pending' then raise exception 'TRADE_UNAVAILABLE'; end if;
 if p_action='cancel' and t.proposer_id=uid then next_status:='cancelled';
 elsif p_action='decline' and t.recipient_id=uid then next_status:='declined';
 else raise exception 'TRADE_ACTION_FORBIDDEN'; end if;
 update public.trade_offers set status=next_status,updated_at=now() where id=t.id;
 delete from public.trade_reserved_cards where trade_id=t.id;
 return true;
end $$;

create or replace function public.expire_trade_offers()
returns integer language plpgsql security definer set search_path=public as $$
declare changed integer;
begin
 update public.trade_offers set status='expired',updated_at=now() where status='pending' and expires_at<=now();
 get diagnostics changed=row_count;
 delete from public.trade_reserved_cards r using public.trade_offers t where r.trade_id=t.id and t.status<>'pending';
 return changed;
end $$;

create or replace function public.fuse_card_copies(p_card uuid,p_from_variant public.card_variant)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); target public.card_variant; needed integer; materials uuid[]; output_id uuid; fusion_id uuid; output_copy public.player_cards;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 perform public.enforce_rate_limit('fuse_cards',8,60);
 if p_from_variant='Standard' then target:='Foil';needed:=5;
 elsif p_from_variant='Foil' then target:='Gold Foil';needed:=3;
 else raise exception 'VARIANT_NOT_FUSIBLE'; end if;
 select array_agg(candidate.id order by candidate.obtained_at,candidate.id) into materials from (
  select pc.id,pc.obtained_at from public.player_cards pc
  where pc.owner_id=uid and pc.card_id=p_card and pc.variant=p_from_variant and pc.retired_at is null
   and not exists(select 1 from public.market_listings l where l.player_card_id=pc.id and l.status='active')
   and not exists(select 1 from public.trade_reserved_cards r where r.player_card_id=pc.id)
  order by pc.obtained_at,pc.id limit needed for update skip locked
 ) candidate;
 if coalesce(cardinality(materials),0)<needed then raise exception 'NOT_ENOUGH_FUSION_COPIES'; end if;
 output_id:=materials[1];
 update public.player_cards set variant=target,updated_at=now() where id=output_id returning * into output_copy;
 update public.player_cards set retired_at=now(),retired_reason='fusion:'||output_id::text,updated_at=now()
 where id=any(materials) and id<>output_id;
 insert into public.card_fusions(owner_id,card_id,output_player_card_id,from_variant,to_variant,material_card_ids,material_count)
 values(uid,p_card,output_id,p_from_variant,target,materials,needed) returning id into fusion_id;
 return jsonb_build_object('fusion_id',fusion_id,'output',to_jsonb(output_copy),'from_variant',p_from_variant,'to_variant',target,'consumed',needed-1);
end $$;

create or replace function public.ensure_friday_market()
returns integer language plpgsql security definer set search_path=public as $$
declare wk text:=to_char(current_date,'IYYY-IW'); inserted_week integer; rec record; count_added integer:=0; generated_price bigint;
begin
 update public.market_listings set status='expired',updated_at=now()
 where status='active' and source_type='system' and ends_at is not null and ends_at<=now();
 if extract(isodow from current_date)<>5 then return 0; end if;
 insert into public.friday_market_weeks(week_key) values(wk) on conflict do nothing;
 get diagnostics inserted_week=row_count;
 if inserted_week=0 then return 0; end if;
 for rec in
  select c.id,c.score from public.cards c
  where c.is_active and c.rarity in ('epic','legendary','mythic','secret')
   and (c.drop_starts_at is null or c.drop_starts_at<=now()) and (c.drop_ends_at is null or c.drop_ends_at>now())
   and (c.max_supply is null or c.minted_supply<c.max_supply)
  order by random() limit 3
 loop
  generated_price:=greatest(50,ceil(greatest(rec.score,1)*(8+random()*12))::bigint);
  insert into public.market_listings(card_id,listing_type,source_type,price,ends_at)
  values(rec.id,'fixed','system',generated_price,now()+interval '7 days');
  count_added:=count_added+1;
 end loop;
 return count_added;
end $$;

create or replace function public.get_card_price_stats(p_card uuid,p_variant public.card_variant default 'Standard')
returns jsonb language plpgsql security definer set search_path=public as $$
declare base_value bigint; avg_value numeric; last_value bigint; sales_count integer; history jsonb;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 select greatest(1,ceil(c.score*10*case p_variant
   when 'Foil' then 1.5 when 'Gold Foil' then 2.5 when 'Black Edition' then 3
   when 'Rainbow Holo' then 4 when 'Animated' then 5 when 'Founder Edition' then 6
   when 'Beta Edition' then 4 else 1 end)::bigint)
 into base_value from public.cards c where c.id=p_card;
 if base_value is null then raise exception 'CARD_NOT_FOUND'; end if;
 select round(avg(coalesce(l.current_bid,l.price)))::numeric,count(*)::integer into avg_value,sales_count
 from public.market_listings l join public.player_cards pc on pc.id=l.player_card_id
 where l.card_id=p_card and coalesce(l.card_variant,pc.variant)=p_variant and l.status='sold';
 select coalesce(l.current_bid,l.price) into last_value
 from public.market_listings l join public.player_cards pc on pc.id=l.player_card_id
 where l.card_id=p_card and coalesce(l.card_variant,pc.variant)=p_variant and l.status='sold'
 order by l.sold_at desc nulls last limit 1;
 select coalesce(jsonb_agg(jsonb_build_object('date',sale_day,'average',average_price,'sales',day_sales) order by sale_day),'[]'::jsonb)
 into history from (
   select date(l.sold_at) as sale_day,round(avg(coalesce(l.current_bid,l.price)))::bigint average_price,count(*)::integer day_sales
   from public.market_listings l join public.player_cards pc on pc.id=l.player_card_id
   where l.card_id=p_card and coalesce(l.card_variant,pc.variant)=p_variant and l.status='sold' and l.sold_at>=current_date-29
   group by date(l.sold_at)
 ) daily;
 return jsonb_build_object('card_id',p_card,'variant',p_variant,'base_price',base_value,
   'average_price',avg_value,'last_price',last_value,'sales_count',sales_count,
   'suggested_price',coalesce(avg_value::bigint,last_value,base_value),'history',history);
end $$;

create or replace function public.set_card_watch(p_card uuid,p_variant public.card_variant,p_target_price bigint default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); result public.card_watchlist;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_target_price is not null and p_target_price<1 then raise exception 'INVALID_PRICE'; end if;
 if not exists(select 1 from public.cards where id=p_card and is_active) then raise exception 'CARD_NOT_FOUND'; end if;
 insert into public.card_watchlist(owner_id,card_id,variant,target_price) values(uid,p_card,p_variant,p_target_price)
 on conflict(owner_id,card_id,variant) do update set target_price=excluded.target_price,updated_at=now() returning * into result;
 return to_jsonb(result);
end $$;

create or replace function public.remove_card_watch(p_card uuid,p_variant public.card_variant)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 delete from public.card_watchlist where owner_id=auth.uid() and card_id=p_card and variant=p_variant;
 return found;
end $$;

create or replace function public.mark_notifications_read(p_notification uuid default null)
returns integer language plpgsql security definer set search_path=public as $$
declare changed integer;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 update public.notifications set read_at=now() where owner_id=auth.uid() and read_at is null and (p_notification is null or id=p_notification);
 get diagnostics changed=row_count; return changed;
end $$;

create or replace function public.refresh_daily_notification()
returns boolean language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); today date:=(timezone('utc',now()))::date;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 if exists(select 1 from public.pack_types where daily and is_active)
  and not exists(select 1 from public.daily_claims where owner_id=uid and claim_date=today)
  and not exists(select 1 from public.notifications where owner_id=uid and type='daily_ready' and metadata->>'ready_date'=today::text) then
  insert into public.notifications(owner_id,type,title,body,metadata) values(uid,'daily_ready','Günlük paketin hazır','Ücretsiz günlük paketini açabilirsin.',jsonb_build_object('ready_date',today));
  return true;
 end if; return false;
end $$;

commit;
