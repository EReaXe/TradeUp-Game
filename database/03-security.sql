begin;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path=public as $$
declare desired text;
begin
 desired:=coalesce(nullif(trim(new.raw_user_meta_data->>'username'),''),'Player-'||left(new.id::text,6));
 begin insert into public.profiles(id,username) values(new.id,desired);
 exception when unique_violation then insert into public.profiles(id,username) values(new.id,left(desired,13)||'-'||left(new.id::text,6)); end;
 insert into public.player_badges(owner_id,badge_id) select new.id,id from public.badges where key='beta-player' on conflict do nothing;
 return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.is_collectverse_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((select is_admin from public.profiles where id=auth.uid()),false);
$$;

create or replace function public.log_admin_change()
returns trigger language plpgsql security definer set search_path=public as $$
declare before_row jsonb; after_row jsonb; before_data jsonb; after_data jsonb; target_id text;
begin
 if not public.is_collectverse_admin() then if tg_op='DELETE' then return old; else return new; end if; end if;
 before_row:=case when tg_op='INSERT' then null else to_jsonb(old) end;
 after_row:=case when tg_op='DELETE' then null else to_jsonb(new) end;
 if tg_op='UPDATE' then
  select coalesce(jsonb_object_agg(b.key,b.value),'{}'::jsonb) into before_data from jsonb_each(before_row)b where after_row->b.key is distinct from b.value;
  select coalesce(jsonb_object_agg(a.key,a.value),'{}'::jsonb) into after_data from jsonb_each(after_row)a where before_row->a.key is distinct from a.value;
 else before_data:=before_row;after_data:=after_row;
 end if;
 target_id:=coalesce(after_row->>'id',before_row->>'id',after_row->>'key',before_row->>'key',after_row->>'owner_id',before_row->>'owner_id');
 insert into public.admin_audit_log(actor_id,action,table_name,record_id,old_data,new_data)
 values(auth.uid(),tg_op,tg_table_name,target_id,before_data,after_data);
 if tg_op='DELETE' then return old; else return new; end if;
end $$;

drop trigger if exists audit_admin_profiles on public.profiles;
create trigger audit_admin_profiles after update on public.profiles for each row execute function public.log_admin_change();
drop trigger if exists audit_admin_cards on public.cards;
create trigger audit_admin_cards after insert or update or delete on public.cards for each row execute function public.log_admin_change();
drop trigger if exists audit_admin_sets on public.card_sets;
create trigger audit_admin_sets after insert or update or delete on public.card_sets for each row execute function public.log_admin_change();
drop trigger if exists audit_admin_packs on public.pack_types;
create trigger audit_admin_packs after insert or update or delete on public.pack_types for each row execute function public.log_admin_change();
drop trigger if exists audit_admin_notes on public.patch_notes;
create trigger audit_admin_notes after insert or update or delete on public.patch_notes for each row execute function public.log_admin_change();
drop trigger if exists audit_admin_settings on public.app_settings;
create trigger audit_admin_settings after insert or update or delete on public.app_settings for each row execute function public.log_admin_change();

alter table public.profiles enable row level security;
alter table public.card_sets enable row level security;
alter table public.cards enable row level security;
alter table public.player_cards enable row level security;
alter table public.player_card_discoveries enable row level security;
alter table public.system_card_pool enable row level security;
alter table public.upgrades enable row level security;
alter table public.player_upgrades enable row level security;
alter table public.pack_types enable row level security;
alter table public.daily_claims enable row level security;
alter table public.badges enable row level security;
alter table public.player_badges enable row level security;
alter table public.patch_notes enable row level security;
alter table public.app_settings enable row level security;
alter table public.rate_limit_buckets enable row level security;
alter table public.economy_events enable row level security;
alter table public.economy_daily_summaries enable row level security;
alter table public.admin_audit_log enable row level security;
alter table public.market_listings enable row level security;
alter table public.market_bids enable row level security;
alter table public.gold_ledger enable row level security;
alter table public.friday_market_weeks enable row level security;
alter table public.trade_offers enable row level security;
alter table public.trade_offer_items enable row level security;
alter table public.trade_reserved_cards enable row level security;
alter table public.card_fusions enable row level security;
alter table public.card_watchlist enable row level security;
alter table public.notifications enable row level security;

drop policy if exists profiles_public_read on public.profiles;
create policy profiles_public_read on public.profiles for select using(true);
drop policy if exists sets_public_read on public.card_sets;
create policy sets_public_read on public.card_sets for select using(is_active);
drop policy if exists cards_public_read on public.cards;
create policy cards_public_read on public.cards for select using(is_active);
drop policy if exists inventories_public_read on public.player_cards;
create policy inventories_public_read on public.player_cards for select using(true);
drop policy if exists player_card_discoveries_owner_read on public.player_card_discoveries;
create policy player_card_discoveries_owner_read on public.player_card_discoveries for select to authenticated using(auth.uid()=owner_id);
drop policy if exists upgrades_public_read on public.upgrades;
create policy upgrades_public_read on public.upgrades for select using(is_active);
drop policy if exists own_upgrades_read on public.player_upgrades;
create policy own_upgrades_read on public.player_upgrades for select to authenticated using(auth.uid()=owner_id);
drop policy if exists packs_public_read on public.pack_types;
create policy packs_public_read on public.pack_types for select using(is_active);
drop policy if exists badges_public_read on public.badges;
create policy badges_public_read on public.badges for select using(is_active);
drop policy if exists player_badges_public_read on public.player_badges;
create policy player_badges_public_read on public.player_badges for select using(true);
drop policy if exists notes_public_read on public.patch_notes;
create policy notes_public_read on public.patch_notes for select using(is_published);
drop policy if exists settings_public_read on public.app_settings;
create policy settings_public_read on public.app_settings for select using(true);
drop policy if exists market_public_read on public.market_listings;
create policy market_public_read on public.market_listings for select using(true);
drop policy if exists market_bids_public_read on public.market_bids;
create policy market_bids_public_read on public.market_bids for select using(true);
drop policy if exists own_ledger_read on public.gold_ledger;
create policy own_ledger_read on public.gold_ledger for select to authenticated using(auth.uid()=owner_id);
drop policy if exists own_economy_events_read on public.economy_events;
create policy own_economy_events_read on public.economy_events for select to authenticated using(auth.uid()=owner_id or public.is_collectverse_admin());
drop policy if exists own_economy_daily_summaries_read on public.economy_daily_summaries;
create policy own_economy_daily_summaries_read on public.economy_daily_summaries for select to authenticated using(auth.uid()=owner_id or public.is_collectverse_admin());
drop policy if exists admin_audit_read on public.admin_audit_log;
create policy admin_audit_read on public.admin_audit_log for select to authenticated using(public.is_collectverse_admin());
drop policy if exists trade_parties_read on public.trade_offers;
create policy trade_parties_read on public.trade_offers for select to authenticated using(auth.uid() in(proposer_id,recipient_id));
drop policy if exists trade_items_parties_read on public.trade_offer_items;
create policy trade_items_parties_read on public.trade_offer_items for select to authenticated using(exists(select 1 from public.trade_offers t where t.id=trade_id and auth.uid() in(t.proposer_id,t.recipient_id)));
drop policy if exists trade_reservations_owner_read on public.trade_reserved_cards;
drop policy if exists trade_reservations_authenticated_read on public.trade_reserved_cards;
create policy trade_reservations_authenticated_read on public.trade_reserved_cards
for select to authenticated
using(exists(select 1 from public.trade_offers t where t.id=trade_id and t.status='pending'));
drop policy if exists card_fusions_owner_read on public.card_fusions;
create policy card_fusions_owner_read on public.card_fusions for select to authenticated using(auth.uid()=owner_id or public.is_collectverse_admin());
drop policy if exists watchlist_owner_read on public.card_watchlist;
create policy watchlist_owner_read on public.card_watchlist for select to authenticated using(auth.uid()=owner_id);
drop policy if exists notifications_owner_read on public.notifications;
create policy notifications_owner_read on public.notifications for select to authenticated using(auth.uid()=owner_id);

drop policy if exists admin_cards_all on public.cards;
create policy admin_cards_all on public.cards for all to authenticated using(public.is_collectverse_admin()) with check(public.is_collectverse_admin());
drop policy if exists admin_sets_all on public.card_sets;
create policy admin_sets_all on public.card_sets for all to authenticated using(public.is_collectverse_admin()) with check(public.is_collectverse_admin());
drop policy if exists admin_packs_all on public.pack_types;
create policy admin_packs_all on public.pack_types for all to authenticated using(public.is_collectverse_admin()) with check(public.is_collectverse_admin());
drop policy if exists admin_notes_all on public.patch_notes;
create policy admin_notes_all on public.patch_notes for all to authenticated using(public.is_collectverse_admin()) with check(public.is_collectverse_admin());
drop policy if exists admin_settings_all on public.app_settings;
create policy admin_settings_all on public.app_settings for all to authenticated using(public.is_collectverse_admin()) with check(public.is_collectverse_admin());

revoke all on all tables in schema public from anon,authenticated;
grant select on public.profiles,public.card_sets,public.cards,public.player_cards,public.player_card_discoveries,public.upgrades,public.player_upgrades,public.pack_types,public.badges,public.player_badges,public.patch_notes,public.app_settings,public.market_listings,public.market_bids,public.gold_ledger,public.economy_events,public.economy_daily_summaries,public.admin_audit_log,public.trade_offers,public.trade_offer_items,public.trade_reserved_cards,public.card_fusions,public.card_watchlist,public.notifications to authenticated;
grant select on public.card_sets,public.cards,public.upgrades,public.pack_types,public.badges,public.patch_notes,public.app_settings to anon;
grant insert,update,delete on public.card_sets,public.cards,public.pack_types,public.patch_notes,public.app_settings to authenticated;

revoke all on function public.sync_energy() from public,anon;
revoke all on function public.produce_energy(integer) from public,anon;
revoke all on function public.buy_upgrade(text) from public,anon;
revoke all on function public.open_pack(text) from public,anon;
revoke all on function public.get_pack_status() from public,anon;
revoke all on function public.convert_energy_to_gold(integer) from public,anon;
revoke all on function public.create_fixed_listing(uuid,bigint) from public,anon;
revoke all on function public.create_auction_listing(uuid,bigint,integer) from public,anon;
revoke all on function public.cancel_market_listing(uuid) from public,anon;
revoke all on function public.buy_market_listing(uuid) from public,anon;
revoke all on function public.place_auction_bid(uuid,bigint) from public,anon;
revoke all on function public.settle_auction(uuid) from public,anon;
revoke all on function public.settle_expired_auctions() from public,anon;
revoke all on function public.sell_card_to_system(uuid) from public,anon;
revoke all on function public.ensure_friday_market() from public,anon;
revoke all on function public.create_trade_offer(uuid,uuid[],uuid[],bigint,bigint,integer) from public,anon;
revoke all on function public.accept_trade_offer(uuid) from public,anon;
revoke all on function public.close_trade_offer(uuid,text) from public,anon;
revoke all on function public.expire_trade_offers() from public,anon;
revoke all on function public.fuse_card_copies(uuid,public.card_variant) from public,anon;
revoke all on function public.get_card_price_stats(uuid,public.card_variant) from public,anon;
revoke all on function public.set_card_watch(uuid,public.card_variant,bigint) from public,anon;
revoke all on function public.remove_card_watch(uuid,public.card_variant) from public,anon;
revoke all on function public.mark_notifications_read(uuid) from public,anon;
revoke all on function public.refresh_daily_notification() from public,anon;
revoke all on function public.get_scoreboard(integer) from public,anon;
revoke all on function public.is_collectverse_admin() from public,anon;
revoke all on function public.enforce_rate_limit(text,integer,integer) from public,anon,authenticated;
revoke all on function public.log_profile_economy_change() from public,anon,authenticated;
revoke all on function public.log_admin_change() from public,anon,authenticated;
revoke all on function public.guard_trade_reserved_card() from public,anon,authenticated;
revoke all on function public.guard_retired_card_use() from public,anon,authenticated;
revoke all on function public.record_player_card_discovery() from public,anon,authenticated;
revoke all on function public.snapshot_market_listing_variant() from public,anon,authenticated;
revoke all on function public.notify_watchlist_price() from public,anon,authenticated;
revoke all on function public.notify_listing_sale() from public,anon,authenticated;
revoke all on function public.notify_outbid() from public,anon,authenticated;
revoke all on function public.notify_maintenance_announcement() from public,anon,authenticated;

grant execute on function public.sync_energy() to authenticated;
grant execute on function public.produce_energy(integer) to authenticated;
grant execute on function public.buy_upgrade(text) to authenticated;
grant execute on function public.open_pack(text) to authenticated;
grant execute on function public.get_pack_status() to authenticated;
grant execute on function public.convert_energy_to_gold(integer) to authenticated;
grant execute on function public.create_fixed_listing(uuid,bigint) to authenticated;
grant execute on function public.create_auction_listing(uuid,bigint,integer) to authenticated;
grant execute on function public.cancel_market_listing(uuid) to authenticated;
grant execute on function public.buy_market_listing(uuid) to authenticated;
grant execute on function public.place_auction_bid(uuid,bigint) to authenticated;
grant execute on function public.settle_expired_auctions() to authenticated;
grant execute on function public.sell_card_to_system(uuid) to authenticated;
grant execute on function public.ensure_friday_market() to authenticated;
grant execute on function public.create_trade_offer(uuid,uuid[],uuid[],bigint,bigint,integer) to authenticated;
grant execute on function public.accept_trade_offer(uuid) to authenticated;
grant execute on function public.close_trade_offer(uuid,text) to authenticated;
grant execute on function public.expire_trade_offers() to authenticated;
grant execute on function public.fuse_card_copies(uuid,public.card_variant) to authenticated;
grant execute on function public.get_card_price_stats(uuid,public.card_variant) to authenticated;
grant execute on function public.set_card_watch(uuid,public.card_variant,bigint) to authenticated;
grant execute on function public.remove_card_watch(uuid,public.card_variant) to authenticated;
grant execute on function public.mark_notifications_read(uuid) to authenticated;
grant execute on function public.refresh_daily_notification() to authenticated;
grant execute on function public.get_scoreboard(integer) to authenticated;
grant execute on function public.is_collectverse_admin() to authenticated;

commit;
