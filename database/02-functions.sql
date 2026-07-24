begin;

create or replace function public.cv_stats(p_user uuid)
returns table(click_power numeric,eps numeric)
language sql security definer stable set search_path=public as $$
with u as (
 select coalesce(sum(case when x.type='click' then pu.level*x.value else 0 end),0) click_add,
        coalesce(sum(case when x.type='eps' then pu.level*x.value else 0 end),0) eps_base
 from public.player_upgrades pu join public.upgrades x on x.key=pu.upgrade_key
 where pu.owner_id=p_user and x.is_active
), c as (
 select coalesce(sum(x.click_bonus),0) click_pct,coalesce(sum(x.eps_bonus),0) eps_pct
 from public.player_cards pc join public.cards x on x.id=pc.card_id where pc.owner_id=p_user and pc.retired_at is null
)
select round((1+u.click_add)*(1+c.click_pct/100),2),round(u.eps_base*(1+c.eps_pct/100),2) from u,c;
$$;

create or replace function public.enforce_rate_limit(p_action text,p_max_hits integer,p_window_seconds integer)
returns void language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); bucket public.rate_limit_buckets;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_action is null or p_max_hits<1 or p_window_seconds<1 then raise exception 'INVALID_RATE_LIMIT'; end if;
 insert into public.rate_limit_buckets(owner_id,action,window_started_at,hits)
 values(uid,p_action,clock_timestamp(),1)
 on conflict(owner_id,action) do update set
  window_started_at=case when public.rate_limit_buckets.window_started_at<=clock_timestamp()-make_interval(secs=>p_window_seconds) then clock_timestamp() else public.rate_limit_buckets.window_started_at end,
  hits=case when public.rate_limit_buckets.window_started_at<=clock_timestamp()-make_interval(secs=>p_window_seconds) then 1 else public.rate_limit_buckets.hits+1 end
 returning * into bucket;
 if bucket.hits>p_max_hits then raise exception 'RATE_LIMITED'; end if;
end $$;

create or replace function public.log_profile_economy_change()
returns trigger language plpgsql security definer set search_path=public as $$
declare
 energy_change numeric:=new.energy-old.energy;
 gold_change bigint:=new.gold-old.gold;
 total_energy_change numeric:=new.total_energy-old.total_energy;
 total_clicks_change bigint:=new.total_clicks-old.total_clicks;
 event_name text:=coalesce(nullif(current_setting('collectverse.event_type',true),''),'balance_change');
begin
 if energy_change<>0 or total_energy_change<>0 or total_clicks_change<>0 then
  insert into public.economy_daily_summaries(owner_id,summary_date,energy_delta,total_energy_delta,total_clicks_delta,update_count,updated_at)
  values(new.id,(timezone('utc',now()))::date,energy_change,total_energy_change,total_clicks_change,1,now())
  on conflict(owner_id,summary_date) do update set
   energy_delta=public.economy_daily_summaries.energy_delta+excluded.energy_delta,
   total_energy_delta=public.economy_daily_summaries.total_energy_delta+excluded.total_energy_delta,
   total_clicks_delta=public.economy_daily_summaries.total_clicks_delta+excluded.total_clicks_delta,
   update_count=public.economy_daily_summaries.update_count+1,
   updated_at=now();
 end if;
 if gold_change<>0 then
  insert into public.economy_events(owner_id,actor_id,event_type,energy_delta,gold_delta,metadata)
  values(new.id,auth.uid(),event_name,energy_change,gold_change,
   jsonb_build_object('total_energy_delta',total_energy_change,'total_clicks_delta',total_clicks_change));
 end if;
 return new;
end $$;

drop trigger if exists profiles_economy_audit on public.profiles;
create trigger profiles_economy_audit after update of energy,gold,total_energy,total_clicks on public.profiles
for each row execute function public.log_profile_economy_change();

create or replace function public.guard_trade_reserved_card()
returns trigger language plpgsql security definer set search_path=public as $$
declare target uuid:=case when tg_table_name='market_listings' then new.player_card_id else old.id end;
begin
 if target is not null and exists(select 1 from public.trade_reserved_cards where player_card_id=target) then raise exception 'CARD_RESERVED_FOR_TRADE'; end if;
 if tg_op='DELETE' then return old; else return new; end if;
end $$;

drop trigger if exists market_trade_reservation_guard on public.market_listings;
create trigger market_trade_reservation_guard before insert or update of player_card_id on public.market_listings for each row execute function public.guard_trade_reserved_card();
drop trigger if exists player_card_trade_reservation_guard on public.player_cards;
create trigger player_card_trade_reservation_guard before delete on public.player_cards for each row execute function public.guard_trade_reserved_card();

create or replace function public.record_player_card_discovery()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.player_card_discoveries(owner_id,card_id,first_discovered_at,last_acquired_at)
 values(new.owner_id,new.card_id,coalesce(new.obtained_at,now()),coalesce(new.obtained_at,now()))
 on conflict(owner_id,card_id) do update
 set last_acquired_at=greatest(public.player_card_discoveries.last_acquired_at,excluded.last_acquired_at);
 return new;
end $$;

drop trigger if exists player_card_discovery_tracker on public.player_cards;
create trigger player_card_discovery_tracker
after insert or update of owner_id on public.player_cards
for each row execute function public.record_player_card_discovery();

create or replace function public.guard_retired_card_use()
returns trigger language plpgsql security definer set search_path=public as $$
declare target uuid:=new.player_card_id;
begin
 if target is not null and exists(select 1 from public.player_cards where id=target and retired_at is not null) then raise exception 'CARD_RETIRED'; end if;
 if tg_op='DELETE' then return old; else return new; end if;
end $$;

drop trigger if exists market_retired_card_guard on public.market_listings;
create trigger market_retired_card_guard before insert or update of player_card_id on public.market_listings for each row execute function public.guard_retired_card_use();

create or replace function public.snapshot_market_listing_variant() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.player_card_id is not null then select variant into new.card_variant from public.player_cards where id=new.player_card_id; end if;
 return new;
end $$;
drop trigger if exists market_listing_variant_snapshot on public.market_listings;
create trigger market_listing_variant_snapshot before insert or update of player_card_id on public.market_listings for each row execute function public.snapshot_market_listing_variant();

create or replace function public.notify_watchlist_price() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status='active' then
  insert into public.notifications(owner_id,type,title,body,reference_id,metadata)
  select w.owner_id,'watchlist_price','İzlediğin kart hedef fiyata indi',c.name||' '||new.price||' Gold fiyatla pazarda.',new.id,
   jsonb_build_object('card_id',new.card_id,'listing_id',new.id,'price',new.price,'variant',coalesce(new.card_variant,'Standard'))
  from public.card_watchlist w join public.cards c on c.id=w.card_id
  where w.card_id=new.card_id and w.variant=coalesce(new.card_variant,'Standard') and w.target_price is not null and new.price<=w.target_price
  on conflict do nothing;
 end if;
 return new;
end $$;
drop trigger if exists market_watchlist_price_alert on public.market_listings;
create trigger market_watchlist_price_alert after insert or update of status,price on public.market_listings for each row execute function public.notify_watchlist_price();

create or replace function public.notify_listing_sale() returns trigger language plpgsql security definer set search_path=public as $$
declare paid bigint;
begin
 if new.status='sold' and old.status is distinct from 'sold' then
  paid:=coalesce(new.current_bid,new.price);
  if new.seller_id is not null then insert into public.notifications(owner_id,type,title,body,reference_id,metadata) values(new.seller_id,'card_sold','Kartın satıldı',paid||' Gold değerinde satış tamamlandı.',new.id,jsonb_build_object('card_id',new.card_id,'price',paid)) on conflict do nothing; end if;
  if new.listing_type='auction' and new.current_bidder is not null then insert into public.notifications(owner_id,type,title,body,reference_id,metadata) values(new.current_bidder,'auction_won','Açık artırmayı kazandın',paid||' Gold karşılığında kart koleksiyonuna eklendi.',new.id,jsonb_build_object('card_id',new.card_id,'price',paid)) on conflict do nothing; end if;
 end if; return new;
end $$;
drop trigger if exists market_sale_notification on public.market_listings;
create trigger market_sale_notification after update of status on public.market_listings for each row execute function public.notify_listing_sale();

create or replace function public.notify_outbid() returns trigger language plpgsql security definer set search_path=public as $$
declare previous_bidder uuid;
begin
 select current_bidder into previous_bidder from public.market_listings where id=new.listing_id;
 if previous_bidder is not null and previous_bidder<>new.bidder_id then
  insert into public.notifications(owner_id,type,title,body,reference_id,metadata) values(previous_bidder,'outbid','Teklifin geçildi','Açık artırmada daha yüksek bir teklif verildi.',new.listing_id,jsonb_build_object('listing_id',new.listing_id,'new_bid',new.amount))
  on conflict(owner_id,type,reference_id) where reference_id is not null do update set metadata=excluded.metadata,read_at=null,created_at=now();
 end if; return new;
end $$;
drop trigger if exists market_bid_outbid_notification on public.market_bids;
create trigger market_bid_outbid_notification after insert on public.market_bids for each row execute function public.notify_outbid();

create or replace function public.notify_maintenance_announcement() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.key='maintenance' and coalesce((new.value->>'enabled')::boolean,false) and (old.value is distinct from new.value) then
  insert into public.notifications(owner_id,type,title,body,metadata)
  select id,'announcement','Bakım duyurusu',coalesce(new.value->>'message','Planlı bakım çalışması başladı.'),jsonb_build_object('estimated_end',new.value->>'estimated_end') from public.profiles;
 end if; return new;
end $$;
drop trigger if exists maintenance_announcement_notification on public.app_settings;
create trigger maintenance_announcement_notification after update on public.app_settings for each row execute function public.notify_maintenance_announcement();
drop trigger if exists trade_retired_card_guard on public.trade_reserved_cards;
create trigger trade_retired_card_guard before insert or update of player_card_id on public.trade_reserved_cards for each row execute function public.guard_retired_card_use();

create or replace function public.sync_energy()
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); p public.profiles; s record; seconds numeric; gain numeric; cap numeric;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into p from public.profiles where id=uid for update;
 if not found then raise exception 'PROFILE_NOT_FOUND'; end if;
 select * into s from public.cv_stats(uid);
 seconds:=least(28800,greatest(0,extract(epoch from now()-p.last_energy_at)));
 cap:=(floor(sqrt(greatest(p.total_energy,0)/250))+1)*1000;
 gain:=least(floor(seconds*coalesce(s.eps,0)),greatest(0,cap-p.energy));
 update public.profiles set energy=least(cap,energy+gain),total_energy=total_energy+gain,last_energy_at=now(),updated_at=now() where id=uid returning * into p;
 return jsonb_build_object('profile',to_jsonb(p),'click_power',s.click_power,'eps',s.eps,'offline_gain',gain);
end $$;

create or replace function public.produce_energy(p_clicks integer default 1)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); p public.profiles; s record; clicks integer; gain numeric; cap numeric;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 perform public.enforce_rate_limit('produce_energy',20,10);
 clicks:=greatest(1,least(coalesce(p_clicks,1),100));
 perform public.sync_energy(); select * into s from public.cv_stats(uid); select * into p from public.profiles where id=uid for update;
 cap:=(floor(sqrt(greatest(p.total_energy,0)/250))+1)*1000;
 gain:=least(clicks*s.click_power,greatest(0,cap-p.energy));
 update public.profiles set energy=least(cap,energy+gain),total_energy=total_energy+gain,total_clicks=total_clicks+clicks,updated_at=now() where id=uid returning * into p;
 return jsonb_build_object('profile',to_jsonb(p),'click_power',s.click_power,'eps',s.eps,'gain',gain);
end $$;

create or replace function public.buy_upgrade(p_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); u public.upgrades; lvl integer:=0; cost numeric; p public.profiles; s record;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 perform public.enforce_rate_limit('buy_upgrade',12,60);
 perform public.sync_energy();
 select * into u from public.upgrades where key=p_key and is_active for share;
 if not found then raise exception 'UPGRADE_NOT_FOUND'; end if;
 select level into lvl from public.player_upgrades where owner_id=uid and upgrade_key=p_key for update;
 lvl:=coalesce(lvl,0);
 if u.max_level is not null and lvl>=u.max_level then raise exception 'UPGRADE_MAX_LEVEL'; end if;
 cost:=floor(u.base_price*power(u.price_growth,lvl));
 update public.profiles set energy=energy-cost,updated_at=now() where id=uid and energy>=cost returning * into p;
 if not found then raise exception 'NOT_ENOUGH_ENERGY'; end if;
 insert into public.player_upgrades(owner_id,upgrade_key,level) values(uid,p_key,1)
 on conflict(owner_id,upgrade_key) do update set level=public.player_upgrades.level+1,updated_at=now();
 select * into s from public.cv_stats(uid);
 return jsonb_build_object('profile',to_jsonb(p),'click_power',s.click_power,'eps',s.eps,'level',lvl+1,'price',cost);
end $$;

create or replace function public.open_pack(p_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); pk public.pack_types; chosen public.cards; pool public.system_card_pool; total numeric; target numeric; rec record; serial integer; copy_id uuid; p public.profiles; recycled boolean:=false;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 perform public.enforce_rate_limit('open_pack',15,60);
 perform public.sync_energy(); select * into pk from public.pack_types where key=p_key and is_active for share;
 if not found then raise exception 'PACK_NOT_FOUND'; end if;
 if pk.daily then
   if exists(select 1 from public.daily_claims where owner_id=uid and pack_key=p_key and created_at>now()-interval '24 hours') then raise exception 'DAILY_ALREADY_CLAIMED'; end if;
   insert into public.daily_claims(owner_id,pack_key) values(uid,p_key) on conflict do nothing;
   if not found then raise exception 'DAILY_ALREADY_CLAIMED'; end if;
 else
   update public.profiles set energy=energy-pk.cost,updated_at=now() where id=uid and energy>=pk.cost returning * into p;
   if not found then raise exception 'NOT_ENOUGH_ENERGY'; end if;
 end if;
 select sum(drop_weight) into total from public.cards c where c.is_active and c.drop_weight>0
   and (c.drop_starts_at is null or c.drop_starts_at<=now()) and (c.drop_ends_at is null or c.drop_ends_at>now())
   and (c.max_supply is null or c.minted_supply<c.max_supply or exists(select 1 from public.system_card_pool sp where sp.card_id=c.id and sp.claimed_at is null))
   and (pk.rarity_floor is null or c.rarity>=pk.rarity_floor);
 if coalesce(total,0)<=0 then raise exception 'NO_AVAILABLE_CARDS'; end if;
 target:=random()*total;
 for rec in select c.* from public.cards c where c.is_active and c.drop_weight>0
   and (c.drop_starts_at is null or c.drop_starts_at<=now()) and (c.drop_ends_at is null or c.drop_ends_at>now())
   and (c.max_supply is null or c.minted_supply<c.max_supply or exists(select 1 from public.system_card_pool sp where sp.card_id=c.id and sp.claimed_at is null))
   and (pk.rarity_floor is null or c.rarity>=pk.rarity_floor)
   order by c.id for update
 loop target:=target-rec.drop_weight; if target<=0 then chosen:=rec; exit; end if; end loop;
 if chosen.id is null then raise exception 'CARD_SELECTION_FAILED'; end if;
 select * into pool from public.system_card_pool where card_id=chosen.id and claimed_at is null order by returned_at,id limit 1 for update skip locked;
 if found then
   recycled:=true; serial:=pool.serial_number;
   insert into public.player_cards(owner_id,card_id,serial_number,variant,condition,obtained_from)
   values(uid,chosen.id,pool.serial_number,pool.variant,pool.condition,'recycled_pack') returning id into copy_id;
   update public.system_card_pool set claimed_at=now(),claimed_by=uid,replacement_player_card_id=copy_id where id=pool.id;
 elsif chosen.max_supply is not null then
   update public.cards set minted_supply=minted_supply+1,updated_at=now() where id=chosen.id and minted_supply<max_supply returning minted_supply into serial;
   if not found then raise exception 'CARD_SOLD_OUT'; end if;
   insert into public.player_cards(owner_id,card_id,serial_number,obtained_from) values(uid,chosen.id,serial,p_key) returning id into copy_id;
 else
   insert into public.player_cards(owner_id,card_id,serial_number,obtained_from) values(uid,chosen.id,null,p_key) returning id into copy_id;
 end if;
 select * into p from public.profiles where id=uid;
 return jsonb_build_object('card',to_jsonb(chosen),'player_card_id',copy_id,'serial_number',serial,'recycled',recycled,'profile',to_jsonb(p));
end $$;

create or replace function public.get_pack_status()
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object(
  'next_daily_at',(select max(dc.created_at)+interval '24 hours' from public.daily_claims dc where dc.owner_id=auth.uid()),
  'available_card_count',(select count(*) from public.cards c where c.is_active and c.drop_weight>0
   and (c.drop_starts_at is null or c.drop_starts_at<=now()) and (c.drop_ends_at is null or c.drop_ends_at>now())
   and (c.max_supply is null or c.minted_supply<c.max_supply or exists(select 1 from public.system_card_pool sp where sp.card_id=c.id and sp.claimed_at is null))),
  'pack_availability',(select coalesce(jsonb_object_agg(pk.key,(
   select count(*) from public.cards c where c.is_active and c.drop_weight>0
    and (c.drop_starts_at is null or c.drop_starts_at<=now()) and (c.drop_ends_at is null or c.drop_ends_at>now())
    and (c.max_supply is null or c.minted_supply<c.max_supply or exists(select 1 from public.system_card_pool sp where sp.card_id=c.id and sp.claimed_at is null))
    and (pk.rarity_floor is null or c.rarity>=pk.rarity_floor)
  )),'{}'::jsonb) from public.pack_types pk where pk.is_active)
 );
$$;

create or replace function public.convert_energy_to_gold(p_gold integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); needed bigint; p public.profiles;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 perform public.enforce_rate_limit('convert_gold',12,60);
 if p_gold is null or p_gold<1 or p_gold>100000 then raise exception 'INVALID_GOLD_AMOUNT'; end if;
 perform public.sync_energy(); needed:=p_gold::bigint*1000;
 update public.profiles set energy=energy-needed,gold=gold+p_gold,updated_at=now() where id=uid and energy>=needed returning * into p;
 if not found then raise exception 'NOT_ENOUGH_ENERGY'; end if;
 insert into public.gold_ledger(owner_id,amount,balance_after,reason) values(uid,p_gold,p.gold,'energy_conversion');
 return jsonb_build_object('profile',to_jsonb(p),'gold_added',p_gold,'energy_spent',needed);
end $$;

create or replace function public.create_fixed_listing(p_player_card uuid,p_price bigint)
returns uuid language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); cid uuid; lid uuid;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 perform public.enforce_rate_limit('create_listing',20,60);
 if p_price is null or p_price<1 then raise exception 'INVALID_PRICE'; end if;
 select card_id into cid from public.player_cards where id=p_player_card and owner_id=uid and retired_at is null for update;
 if not found then raise exception 'CARD_COPY_NOT_FOUND'; end if;
 if exists(select 1 from public.trade_reserved_cards where player_card_id=p_player_card) then raise exception 'CARD_RESERVED_FOR_TRADE'; end if;
 insert into public.market_listings(seller_id,player_card_id,card_id,listing_type,price) values(uid,p_player_card,cid,'fixed',p_price) returning id into lid;
 return lid;
end $$;

create or replace function public.create_auction_listing(p_player_card uuid,p_base_price bigint,p_duration_days integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); cid uuid; lid uuid; fee numeric; finish timestamptz;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 perform public.enforce_rate_limit('create_listing',20,60);
 if p_base_price is null or p_base_price<1 then raise exception 'INVALID_PRICE'; end if;
 if p_duration_days is null or p_duration_days<1 or p_duration_days>6 then raise exception 'INVALID_AUCTION_DURATION'; end if;
 select card_id into cid from public.player_cards where id=p_player_card and owner_id=uid and retired_at is null for update;
 if not found then raise exception 'CARD_COPY_NOT_FOUND'; end if;
 if exists(select 1 from public.trade_reserved_cards where player_card_id=p_player_card) then raise exception 'CARD_RESERVED_FOR_TRADE'; end if;
 fee:=least(0.5,(p_duration_days-1)*0.1); finish:=now()+make_interval(days=>p_duration_days);
 insert into public.market_listings(seller_id,player_card_id,card_id,listing_type,price,commission_rate,ends_at)
 values(uid,p_player_card,cid,'auction',p_base_price,fee,finish) returning id into lid;
 return jsonb_build_object('listing_id',lid,'commission_rate',fee,'ends_at',finish);
end $$;

create or replace function public.cancel_market_listing(p_listing uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); l public.market_listings;
begin
 select * into l from public.market_listings where id=p_listing and seller_id=uid for update;
 if not found then raise exception 'LISTING_NOT_FOUND'; end if;
 if l.status<>'active' then raise exception 'LISTING_NOT_ACTIVE'; end if;
 if l.listing_type='auction' and l.current_bidder is not null then raise exception 'AUCTION_HAS_BIDS'; end if;
 update public.market_listings set status='cancelled',updated_at=now() where id=l.id; return true;
end $$;

create or replace function public.get_scoreboard(p_limit integer default 100)
returns table(user_id uuid,username text,avatar_url text,total_energy numeric,total_clicks bigint,created_at timestamptz,collection_score bigint,unique_cards bigint,total_cards bigint,level integer,rank bigint)
language sql security definer stable set search_path=public as $$
with stats as (
 select p.id,p.username,p.avatar_url,p.total_energy,p.total_clicks,p.created_at,coalesce(sum(c.score*case pc.variant when 'Foil' then 1.5 when 'Gold Foil' then 2.5 when 'Black Edition' then 3 when 'Rainbow Holo' then 4 when 'Animated' then 5 when 'Founder Edition' then 6 when 'Beta Edition' then 4 else 1 end),0)::bigint collection_score,
 count(distinct pc.card_id)::bigint unique_cards,count(pc.id)::bigint total_cards
 from public.profiles p left join public.player_cards pc on pc.owner_id=p.id and pc.retired_at is null left join public.cards c on c.id=pc.card_id group by p.id
), ranked as (
 select s.*,(floor(sqrt(greatest(s.total_energy,0)/250))+1)::integer level,
 row_number() over(order by s.collection_score desc,s.total_energy desc,s.created_at asc)::bigint rank from stats s
)
select id,username,avatar_url,total_energy,total_clicks,created_at,collection_score,unique_cards,total_cards,level,rank
from ranked order by rank limit greatest(1,least(coalesce(p_limit,100),500));
$$;

commit;
