-- Phase 12. Prerequisite 011. Escrow is owned game money, not revenue.
begin;
alter table public.stores add column if not exists trading_escrow_kurus bigint not null default 0 check(trading_escrow_kurus between 0 and 9000000000000000);
alter table public.transactions drop constraint if exists transactions_type_check;
alter table public.transactions add constraint transactions_type_check check(type in ('INITIAL_CAPITAL','WHOLESALE_PURCHASE','MARKETPLACE_PURCHASE','MARKETPLACE_SALE','NPC_SALE','MARKETPLACE_FEE','WAREHOUSE_UPGRADE','OFFICE_UPGRADE','ADVERTISEMENT','SALARY','LOAN','LOAN_PAYMENT','REWARD','ESCROW_HOLD','ESCROW_REFUND'));
alter table public.marketplace_listings drop constraint if exists marketplace_listings_status_check;
alter table public.marketplace_listings add constraint marketplace_listings_status_check check(status in ('active','sold','cancelled','contract','auction'));
create table if not exists public.serial_counters(product_id uuid primary key references public.products(id),last_number bigint not null check(last_number>0));
create table if not exists public.serial_items(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id),serial_number bigint not null,owner_store_id uuid not null references public.stores(id),created_at timestamptz not null default now(),unique(product_id,serial_number));
create table if not exists public.player_contracts(id uuid primary key references public.marketplace_listings(id),recipient_store_id uuid not null references public.stores(id),status text not null default 'pending' check(status in ('pending','accepted','declined','cancelled','expired')),ends_at timestamptz not null);
create table if not exists public.player_auctions(id uuid primary key references public.marketplace_listings(id),serial_id uuid not null references public.serial_items(id),ends_at timestamptz not null,status text not null default 'open' check(status in ('open','claimed','cancelled')),highest_bidder uuid references public.stores(id),highest_bid_kurus bigint not null default 0 check(highest_bid_kurus between 0 and 1000000000000),bid_count integer not null default 0);
create unique index if not exists auction_one_serial on public.player_auctions(serial_id) where status='open';
create index if not exists auctions_end on public.player_auctions(status,ends_at);
create table if not exists public.trading_receipts(store_id uuid not null references public.stores(id),request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,created_at timestamptz not null default now(),primary key(store_id,request_id));
do $$declare t text;begin
 foreach t in array array['serial_counters','serial_items','player_contracts','player_auctions','trading_receipts'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);end loop;
 foreach t in array array['serial_items','trading_receipts'] loop execute format('grant select on public.%I to authenticated',t);execute format('drop policy if exists trading_own on public.%I',t);end loop;
end;$$;
create policy trading_own on public.serial_items for select to authenticated using(exists(select 1 from public.stores s where s.id=owner_store_id and s.user_id=(select auth.uid())));
create policy trading_own on public.trading_receipts for select to authenticated using(exists(select 1 from public.stores s where s.id=store_id and s.user_id=(select auth.uid())));
drop trigger if exists trading_receipt_immutable on public.trading_receipts;
create trigger trading_receipt_immutable before update or delete on public.trading_receipts for each row execute function public.reject_ledger_mutation();

create or replace function public.trading_escrow(p_store uuid,p_amount bigint,p_key text)
returns void language plpgsql security definer set search_path='' as $$
declare s public.stores;
begin
 select * into s from public.stores where id=p_store for update;
 if p_amount>0 and (s.cash_kurus<p_amount or s.trading_escrow_kurus>9000000000000000-p_amount) then raise exception 'Insufficient cash' using errcode='W0005';end if;
 if p_amount<0 and (s.trading_escrow_kurus< -p_amount or s.cash_kurus>9000000000000000+p_amount) then raise exception 'Refund balance limit' using errcode='T0010';end if;
 update public.stores set cash_kurus=cash_kurus-p_amount,trading_escrow_kurus=trading_escrow_kurus+p_amount where id=p_store;
 insert into public.transactions(user_id,store_id,type,amount_kurus,balance_after_kurus,idempotency_key) values(s.user_id,s.id,case when p_amount>0 then 'ESCROW_HOLD' else 'ESCROW_REFUND' end,-p_amount,s.cash_kurus-p_amount,p_key);
end;$$;
revoke all on function public.trading_escrow(uuid,bigint,text) from public,anon,authenticated;

create or replace function public.trade_action(p_action text,p_payload jsonb,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare me uuid;other uuid;seller uuid;previous uuid;v_id uuid;v_product uuid;v_serial uuid;v_number bigint;v_qty integer;v_price bigint;v_duration integer;v_at timestamptz;
 s public.stores;l public.marketplace_listings;a public.player_auctions;c public.player_contracts;i public.serial_items;r public.trading_receipts;v_result jsonb;v_trade jsonb;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000';end if;
 if p_action is null or p_payload is null or jsonb_typeof(p_payload)<>'object' or p_request_id is null then raise exception 'Invalid request' using errcode='T0001';end if;
 select id into me from public.stores where user_id=auth.uid();if me is null then raise exception 'Store required' using errcode='W0001';end if;
 select * into r from public.trading_receipts where store_id=me and request_id=p_request_id;
 if found then if r.action<>p_action or r.payload<>p_payload then raise exception 'Request changed' using errcode='T0002';end if;return r.result;end if;
 if p_action='contract_create' then select id into other from public.stores where lower(store_name)=lower(btrim(p_payload->>'recipient'));if other is null or other=me then raise exception 'Other store required' using errcode='T0003';end if;
 elsif p_action in('contract_accept','contract_decline','contract_cancel') then
  v_id:=(p_payload->>'id')::uuid;select * into c from public.player_contracts where id=v_id;select * into l from public.marketplace_listings where id=v_id;
  if c.id is null then raise exception 'Contract unavailable' using errcode='T0004';end if;seller:=l.seller_store_id;other:=c.recipient_store_id;
 elsif p_action='auction_create' then v_serial:=(p_payload->>'serial_id')::uuid;select * into i from public.serial_items where id=v_serial;if i.id is null or i.owner_store_id<>me then raise exception 'Serial item not owned' using errcode='T0005';end if;
 elsif p_action in('auction_bid','auction_claim','auction_cancel') then
  v_id:=(p_payload->>'id')::uuid;select * into a from public.player_auctions where id=v_id;select * into l from public.marketplace_listings where id=v_id;
  if a.id is null then raise exception 'Auction unavailable' using errcode='T0004';end if;seller:=l.seller_store_id;previous:=a.highest_bidder;
 elsif p_action<>'serialize' then raise exception 'Unknown action' using errcode='T0001';end if;
 -- Read participant identities, lock all stores in UUID order, then revalidate the row.
 perform id from public.stores where id in(me,other,seller,previous) order by id for update;
 select * into r from public.trading_receipts where store_id=me and request_id=p_request_id;
 if found then if r.action<>p_action or r.payload<>p_payload then raise exception 'Request changed' using errcode='T0002';end if;return r.result;end if;
 select * into s from public.stores where id=me;v_at:=clock_timestamp();
 if p_action in('serialize','contract_create','auction_create','auction_bid') then
  perform public.sync_store_progression(me);if p_action<>'serialize' and (select level from public.stores where id=me)<5 then raise exception 'Trading requires level 5' using errcode='G0001';end if;
 end if;
 if p_action='serialize' then
  v_product:=(p_payload->>'product_id')::uuid;
  perform id from public.products where id=v_product and rarity in('Rare','Epic','Legendary') for update;if not found then raise exception 'Rare product required' using errcode='T0005';end if;
  if not exists(select 1 from public.inventory where store_id=me and product_id=v_product and quantity>reserved_quantity) then raise exception 'Available stock required' using errcode='M0003';end if;
  insert into public.serial_counters values(v_product,1) on conflict(product_id) do update set last_number=serial_counters.last_number+1 returning last_number into v_number;
  insert into public.serial_items(product_id,serial_number,owner_store_id) values(v_product,v_number,me) returning id into v_serial;
  update public.inventory set reserved_quantity=reserved_quantity+1 where store_id=me and product_id=v_product;
  v_result:=jsonb_build_object('status','serialized','serial_id',v_serial,'serial_number',v_number::text);
 elsif p_action in('contract_create','auction_create') then
  if (select count(*) from public.marketplace_listings where seller_store_id=me and status in('active','contract','auction'))>=s.listing_limit then raise exception 'Listing limit' using errcode='M0002';end if;
  v_price:=(p_payload->>'price_kurus')::bigint;if v_price is null or v_price not between 1 and 1000000000000 then raise exception 'Invalid price' using errcode='T0001';end if;
  if p_action='contract_create' then
   v_product:=(p_payload->>'product_id')::uuid;v_qty:=(p_payload->>'quantity')::integer;
   v_id:=public.create_marketplace_listing_phase7(v_product,v_qty,v_price,p_request_id);
   update public.marketplace_listings set status='contract' where id=v_id;
   insert into public.player_contracts(id,recipient_store_id,ends_at) values(v_id,other,v_at+interval '24 hours');
  else
   select * into i from public.serial_items where id=v_serial for update;if i.owner_store_id<>me then raise exception 'Serial owner changed' using errcode='T0012';end if;
   v_duration:=(p_payload->>'duration_minutes')::integer;if v_duration is null or v_duration not in(5,30,60) then raise exception 'Invalid duration' using errcode='T0001';end if;
   if exists(select 1 from public.player_auctions where serial_id=v_serial and status='open') then raise exception 'Item already auctioned' using errcode='T0006';end if;
   insert into public.marketplace_listings(seller_store_id,product_id,quantity,original_quantity,unit_price_kurus,status,request_id) values(me,i.product_id,1,1,v_price,'auction',p_request_id) returning id into v_id;
   insert into public.player_auctions(id,serial_id,ends_at) values(v_id,v_serial,v_at+make_interval(mins=>v_duration));
  end if;
  v_result:=jsonb_build_object('status','created','id',v_id);
 elsif p_action like 'contract_%' then
  select * into c from public.player_contracts where id=v_id for update;select * into l from public.marketplace_listings where id=v_id;
  if me not in(seller,other) then raise exception 'Not a contract party' using errcode='T0007';end if;
  if c.status<>'pending' then raise exception 'Contract closed' using errcode='T0004';end if;
  if (p_action in('contract_accept','contract_decline') and me<>other) or (p_action='contract_cancel' and me<>seller) then raise exception 'Wrong party' using errcode='T0007';end if;
  if v_at>=c.ends_at or p_action<>'contract_accept' then
   update public.inventory set reserved_quantity=reserved_quantity-l.quantity where store_id=seller and product_id=l.product_id;
   update public.marketplace_listings set status='cancelled',quantity=0 where id=v_id;
   update public.player_contracts set status=case when v_at>=ends_at then 'expired' when p_action='contract_decline' then 'declined' else 'cancelled' end where id=v_id returning * into c;
   v_result:=jsonb_build_object('status',c.status,'id',v_id);
  else
   if (select level from public.stores where id=me)<5 then raise exception 'Trading requires level 5' using errcode='G0001';end if;
   update public.marketplace_listings set status='active' where id=v_id;
   v_trade:=public.buy_marketplace_listing_phase7(v_id,l.quantity,l.unit_price_kurus,p_request_id);
   update public.player_contracts set status='accepted' where id=v_id;
   perform public.sync_store_progression(seller);perform public.sync_store_progression(me);
   v_result:=v_trade||jsonb_build_object('status','accepted','id',v_id);
  end if;
 else
  select * into a from public.player_auctions where id=v_id for update;select * into l from public.marketplace_listings where id=v_id;
  if a.highest_bidder is distinct from previous then raise exception 'Bid changed; retry' using errcode='T0012';end if;
  if a.status<>'open' then raise exception 'Auction closed' using errcode='T0004';end if;
  if p_action='auction_bid' then
   if me=seller or v_at>=a.ends_at then raise exception 'Auction not biddable' using errcode='T0008';end if;
   if me is distinct from previous and (select count(*) from public.player_auctions where status='open' and highest_bidder=me)>=10 then raise exception 'At most ten winning bids' using errcode='T0013';end if;
   v_price:=(p_payload->>'amount_kurus')::bigint;
   if v_price is null or v_price not between 1 and 1000000000000 or v_price<greatest(l.unit_price_kurus,a.highest_bid_kurus+greatest(1,ceil(a.highest_bid_kurus::numeric*0.05)::bigint)) then raise exception 'Bid too low' using errcode='T0009';end if;
   if previous is not null then perform public.trading_escrow(previous,-a.highest_bid_kurus,'bid-refund:'||p_request_id::text);end if;
   perform public.trading_escrow(me,v_price,'bid-hold:'||p_request_id::text);
   update public.player_auctions set highest_bidder=me,highest_bid_kurus=v_price,bid_count=bid_count+1 where id=v_id;
   v_result:=jsonb_build_object('status','bid','id',v_id,'amount_kurus',v_price::text);
  elsif p_action='auction_claim' then
   if me is distinct from a.highest_bidder or v_at<a.ends_at or v_at>=a.ends_at+interval '24 hours' then raise exception 'Winner claim unavailable' using errcode='T0011';end if;
   perform public.trading_escrow(me,-a.highest_bid_kurus,'claim-release:'||p_request_id::text);
   update public.marketplace_listings set status='active',unit_price_kurus=a.highest_bid_kurus where id=v_id;
   v_trade:=public.buy_marketplace_listing_phase7(v_id,1,a.highest_bid_kurus,p_request_id);
   update public.inventory set reserved_quantity=reserved_quantity+1 where store_id=me and product_id=l.product_id;
   update public.serial_items set owner_store_id=me where id=a.serial_id;
   update public.player_auctions set status='claimed' where id=v_id;
   perform public.sync_store_progression(seller);perform public.sync_store_progression(me);
   v_result:=v_trade||jsonb_build_object('status','claimed','id',v_id,'serial_id',a.serial_id);
  else
   if me<>seller and me is distinct from a.highest_bidder then raise exception 'Not an auction party' using errcode='T0007';end if;
   if a.highest_bidder is not null and v_at<a.ends_at+interval '24 hours' then raise exception 'Winning bid is binding until claim deadline' using errcode='T0011';end if;
   if a.highest_bidder is null and me<>seller then raise exception 'Seller required' using errcode='T0007';end if;
   if a.highest_bidder is not null then perform public.trading_escrow(a.highest_bidder,-a.highest_bid_kurus,'auction-refund:'||p_request_id::text);end if;
   update public.marketplace_listings set status='cancelled',quantity=0 where id=v_id;update public.player_auctions set status='cancelled' where id=v_id;
   v_result:=jsonb_build_object('status','cancelled','id',v_id);
  end if;
 end if;
 insert into public.trading_receipts(store_id,request_id,action,payload,result) values(me,p_request_id,p_action,p_payload,v_result);return v_result;
end;$$;
revoke all on function public.trade_action(text,jsonb,uuid) from public,anon,authenticated;grant execute on function public.trade_action(text,jsonb,uuid) to authenticated;

create or replace function public.my_advanced_trading()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare me uuid;v_at timestamptz:=clock_timestamp();v_auctions jsonb;v_contracts jsonb;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='28000';end if;select id into me from public.stores where user_id=auth.uid();if me is null then raise exception 'Store required' using errcode='W0001';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',p.name,'serial_number',si.serial_number::text,'seller',st.store_name,'mine',st.id=me,'winning',coalesce(a.highest_bidder=me,false),'bid_kurus',a.highest_bid_kurus::text,'minimum_kurus',greatest(l.unit_price_kurus,a.highest_bid_kurus+greatest(1,ceil(a.highest_bid_kurus::numeric*0.05)::bigint))::text,'bid_count',a.bid_count,'ends_at',a.ends_at,'claim_deadline',a.ends_at+interval '24 hours','status',a.status) order by a.ends_at),'[]'::jsonb) into v_auctions
 from (select * from public.player_auctions a where status='open' order by case when highest_bidder=me or exists(select 1 from public.marketplace_listings l where l.id=a.id and l.seller_store_id=me) then 0 else 1 end,ends_at limit 50) a join public.marketplace_listings l on l.id=a.id join public.products p on p.id=l.product_id join public.serial_items si on si.id=a.serial_id join public.stores st on st.id=l.seller_store_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',p.name,'seller',st.store_name,'recipient',bt.store_name,'incoming',c.recipient_store_id=me,'quantity',l.original_quantity,'price_kurus',l.unit_price_kurus::text,'status',c.status,'ends_at',c.ends_at) order by l.created_at desc),'[]'::jsonb) into v_contracts
 from (select c.* from public.player_contracts c join public.marketplace_listings l on l.id=c.id where l.seller_store_id=me or c.recipient_store_id=me order by l.created_at desc limit 50) c join public.marketplace_listings l on l.id=c.id join public.products p on p.id=l.product_id join public.stores st on st.id=l.seller_store_id join public.stores bt on bt.id=c.recipient_store_id;
 return jsonb_build_object('as_of',v_at,'level',(select level from public.stores where id=me),'cash_kurus',(select cash_kurus::text from public.stores where id=me),'escrow_kurus',(select trading_escrow_kurus::text from public.stores where id=me),'fee_bps',(select marketplace_fee_bps from public.economy_settings where id),
 'items',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'rarity',p.rarity,'available',i.quantity-i.reserved_quantity,'quantity',i.quantity,'market_price_kurus',p.market_price_kurus::text) order by p.name),'[]'::jsonb) from public.inventory i join public.products p on p.id=i.product_id where store_id=me and quantity>0),
 'serials',(select coalesce(jsonb_agg(jsonb_build_object('id',si.id,'name',p.name,'rarity',p.rarity,'serial_number',si.serial_number::text,'auctioned',exists(select 1 from public.player_auctions a where a.serial_id=si.id and a.status='open')) order by si.created_at desc),'[]'::jsonb) from public.serial_items si join public.products p on p.id=si.product_id where owner_store_id=me),
 'collection',(select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'rarity',p.rarity,'owned',coalesce(i.quantity,0)>0,'quantity',coalesce(i.quantity,0)) order by p.rarity,p.name) from public.products p left join public.inventory i on i.product_id=p.id and i.store_id=me where p.rarity in('Rare','Epic','Legendary')),
 'auctions',v_auctions,'contracts',v_contracts,'receipts',(select coalesce(jsonb_agg(jsonb_build_object('action',r.action,'result',r.result,'created_at',r.created_at) order by r.created_at desc),'[]'::jsonb) from(select * from public.trading_receipts where store_id=me order by created_at desc limit 20) r));
end;$$;
revoke all on function public.my_advanced_trading() from public,anon,authenticated;grant execute on function public.my_advanced_trading() to authenticated;

-- Add escrow to all existing net-worth authorities, once, preserving their return types.
do $$declare f text;d text;begin
 foreach f in array array['public.my_dashboard_phase7()','public.progression_metrics(uuid,timestamptz,timestamptz)','public.my_net_worth_kurus()'] loop
 d:=pg_get_functiondef(to_regprocedure(f));if position('trading_escrow_kurus' in d)=0 then
 d:=replace(d,'v_store.cash_kurus::numeric+v_value','v_store.cash_kurus::numeric+v_store.trading_escrow_kurus+v_value');
 d:=replace(d,'s.cash_kurus+s.business_assets_kurus::numeric','s.cash_kurus+s.trading_escrow_kurus+s.business_assets_kurus::numeric');
 d:=replace(d,'s.cash_kurus::numeric+s.business_assets_kurus','s.cash_kurus::numeric+s.trading_escrow_kurus+s.business_assets_kurus');execute d;end if;
 end loop;
end;$$;
-- Share the listing limit across ordinary listings, contracts and auctions.
do $$declare d text;begin
 d:=pg_get_functiondef('public.create_marketplace_listing_phase7(uuid,integer,bigint,uuid)'::regprocedure);
 d:=replace(d,$old$status='active')>=s.listing_limit$old$,$new$status in ('active','contract','auction'))>=s.listing_limit$new$);
 execute d;
end;$$;
commit;
