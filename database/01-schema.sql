begin;

create extension if not exists pgcrypto;

do $$ begin create type public.card_rarity as enum ('common','uncommon','rare','epic','legendary','mythic','secret'); exception when duplicate_object then null; end $$;
do $$ begin create type public.card_variant as enum ('Standard','Foil','Gold Foil','Black Edition','Rainbow Holo','Animated','Founder Edition','Beta Edition'); exception when duplicate_object then null; end $$;
do $$ begin create type public.card_condition as enum ('Mint','Near Mint','Excellent','Good','Played'); exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  username_normalized text generated always as (lower(trim(username))) stored,
  avatar_url text,
  energy numeric(20,2) not null default 0 check (energy >= 0),
  total_energy numeric(24,2) not null default 0 check (total_energy >= 0),
  total_clicks bigint not null default 0 check (total_clicks >= 0),
  gold bigint not null default 0 check (gold >= 0),
  is_admin boolean not null default false,
  last_energy_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_length check (char_length(trim(username)) between 3 and 20),
  constraint profiles_username_unique unique (username_normalized)
);

create table if not exists public.card_sets (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.cards (
  id uuid primary key default gen_random_uuid(),
  set_id uuid references public.card_sets(id) on delete set null,
  code text not null unique,
  name text not null,
  subtitle text,
  description text not null default '',
  image_url text,
  symbol text not null default '✦',
  rarity public.card_rarity not null,
  illustrator text,
  series_name text,
  season_name text,
  edition_name text not null default 'Standard Edition',
  card_number integer,
  total_in_set integer,
  power integer not null default 0 check (power >= 0),
  score integer not null default 0 check (score >= 0),
  click_bonus numeric(8,2) not null default 0 check (click_bonus >= 0),
  eps_bonus numeric(8,2) not null default 0 check (eps_bonus >= 0),
  drop_weight numeric(14,6) not null default 1 check (drop_weight >= 0),
  max_supply integer check (max_supply is null or max_supply > 0),
  minted_supply integer not null default 0 check (minted_supply >= 0),
  is_limited boolean not null default false,
  is_signed boolean not null default false,
  release_date date,
  drop_starts_at timestamptz,
  drop_ends_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cards_supply_valid check (max_supply is null or minted_supply <= max_supply),
  constraint cards_number_valid check (card_number is null or card_number > 0),
  constraint cards_total_valid check (total_in_set is null or total_in_set > 0),
  constraint cards_number_in_set check (card_number is null or total_in_set is null or card_number <= total_in_set)
);

create table if not exists public.player_cards (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  card_id uuid not null references public.cards(id) on delete restrict,
  serial_number integer,
  variant public.card_variant not null default 'Standard',
  condition public.card_condition not null default 'Mint',
  obtained_from text not null default 'pack',
  obtained_at timestamptz not null default now(),
  retired_at timestamptz,
  retired_reason text,
  updated_at timestamptz not null default now(),
  constraint player_cards_serial_positive check (serial_number is null or serial_number > 0),
  constraint player_cards_limited_serial unique (card_id,serial_number)
);

create table if not exists public.player_card_discoveries (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  card_id uuid not null references public.cards(id) on delete cascade,
  first_discovered_at timestamptz not null default now(),
  last_acquired_at timestamptz not null default now(),
  primary key(owner_id,card_id)
);

create table if not exists public.system_card_pool (
  id uuid primary key default gen_random_uuid(),
  original_player_card_id uuid not null,
  card_id uuid not null references public.cards(id) on delete restrict,
  serial_number integer,
  variant public.card_variant not null,
  condition public.card_condition not null,
  returned_by uuid references public.profiles(id) on delete set null,
  returned_at timestamptz not null default now(),
  claimed_at timestamptz,
  claimed_by uuid references public.profiles(id) on delete set null,
  replacement_player_card_id uuid,
  constraint system_pool_serial_positive check (serial_number is null or serial_number > 0)
);

create table if not exists public.upgrades (
  key text primary key,
  name text not null,
  icon text,
  description text not null default '',
  type text not null check (type in ('click','eps')),
  base_price numeric(20,2) not null check (base_price >= 0),
  value numeric(20,4) not null default 0 check (value >= 0),
  price_growth numeric(8,4) not null default 1.55 check (price_growth >= 1),
  max_level integer check (max_level is null or max_level > 0),
  sort_order integer not null default 0,
  is_active boolean not null default true
);

create table if not exists public.player_upgrades (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  upgrade_key text not null references public.upgrades(key) on delete restrict,
  level integer not null default 0 check (level >= 0),
  updated_at timestamptz not null default now(),
  primary key(owner_id,upgrade_key)
);

create table if not exists public.pack_types (
  key text primary key,
  name text not null,
  description text not null default '',
  cost numeric(20,2) not null default 0 check (cost >= 0),
  rarity_floor public.card_rarity,
  daily boolean not null default false,
  sort_order integer not null default 0,
  is_active boolean not null default true
);

create table if not exists public.daily_claims (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  pack_key text not null references public.pack_types(key) on delete restrict,
  claim_date date not null default (timezone('utc',now()))::date,
  created_at timestamptz not null default now(),
  primary key(owner_id,pack_key,claim_date)
);

create table if not exists public.badges (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  description text not null default '',
  icon text,
  is_active boolean not null default true
);

create table if not exists public.player_badges (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade,
  awarded_at timestamptz not null default now(),
  primary key(owner_id,badge_id)
);

create table if not exists public.patch_notes (
  id uuid primary key default gen_random_uuid(),
  version text not null unique,
  title text not null,
  body text not null,
  changes jsonb not null default '[]'::jsonb check (jsonb_typeof(changes)='array'),
  published_at timestamptz not null default now(),
  is_published boolean not null default false
);

create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.rate_limit_buckets (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  action text not null,
  window_started_at timestamptz not null default clock_timestamp(),
  hits integer not null default 0 check (hits >= 0),
  primary key(owner_id,action)
);

create table if not exists public.economy_events (
  id bigint generated always as identity primary key,
  owner_id uuid references public.profiles(id) on delete set null,
  actor_id uuid references public.profiles(id) on delete set null,
  event_type text not null,
  energy_delta numeric(24,2) not null default 0,
  gold_delta bigint not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.economy_daily_summaries (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  summary_date date not null default (timezone('utc',now()))::date,
  energy_delta numeric(24,2) not null default 0,
  total_energy_delta numeric(24,2) not null default 0,
  total_clicks_delta bigint not null default 0,
  update_count integer not null default 0 check(update_count>=0),
  updated_at timestamptz not null default now(),
  primary key(owner_id,summary_date)
);

create table if not exists public.admin_audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  table_name text not null,
  record_id text,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.market_listings (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid references public.profiles(id) on delete set null,
  player_card_id uuid references public.player_cards(id) on delete restrict,
  card_id uuid not null references public.cards(id) on delete restrict,
  card_variant public.card_variant,
  listing_type text not null check (listing_type in ('fixed','auction')),
  source_type text not null default 'player' check (source_type in ('player','system')),
  price bigint not null check (price > 0),
  current_bid bigint check (current_bid is null or current_bid > 0),
  current_bidder uuid references public.profiles(id) on delete set null,
  commission_rate numeric(4,3) not null default 0 check (commission_rate between 0 and 0.5),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  status text not null default 'active' check (status in ('active','sold','cancelled','expired')),
  sold_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint market_source_valid check ((source_type='player' and seller_id is not null and player_card_id is not null) or (source_type='system' and seller_id is null and player_card_id is null)),
  constraint market_auction_end check (listing_type='fixed' or ends_at is not null)
);

create table if not exists public.market_bids (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.market_listings(id) on delete cascade,
  bidder_id uuid not null references public.profiles(id) on delete cascade,
  amount bigint not null check (amount > 0),
  created_at timestamptz not null default now()
);

create table if not exists public.gold_ledger (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  amount bigint not null check (amount <> 0),
  balance_after bigint not null check (balance_after >= 0),
  reason text not null,
  reference_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.friday_market_weeks (
  week_key text primary key,
  created_at timestamptz not null default now()
);

create table if not exists public.trade_offers (
  id uuid primary key default gen_random_uuid(),
  proposer_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  offered_gold bigint not null default 0 check (offered_gold >= 0),
  requested_gold bigint not null default 0 check (requested_gold >= 0),
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled','expired')),
  expires_at timestamptz not null default (now()+interval '48 hours'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trade_distinct_players check (proposer_id<>recipient_id)
);

create table if not exists public.trade_offer_items (
  trade_id uuid not null references public.trade_offers(id) on delete cascade,
  player_card_id uuid not null references public.player_cards(id) on delete restrict,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  side text not null check (side in ('offered','requested')),
  primary key(trade_id,player_card_id)
);

create table if not exists public.trade_reserved_cards (
  player_card_id uuid primary key references public.player_cards(id) on delete cascade,
  trade_id uuid not null references public.trade_offers(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  reserved_at timestamptz not null default now()
);

create table if not exists public.card_fusions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  card_id uuid not null references public.cards(id) on delete restrict,
  output_player_card_id uuid not null references public.player_cards(id) on delete restrict,
  from_variant public.card_variant not null,
  to_variant public.card_variant not null,
  material_card_ids uuid[] not null,
  material_count integer not null check (material_count > 1),
  created_at timestamptz not null default now()
);

create table if not exists public.card_watchlist (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  card_id uuid not null references public.cards(id) on delete cascade,
  variant public.card_variant not null default 'Standard',
  target_price bigint check (target_price is null or target_price > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(owner_id,card_id,variant)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null default '',
  reference_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists player_cards_owner_obtained_idx on public.player_cards(owner_id,obtained_at desc);
create index if not exists system_card_pool_available_idx on public.system_card_pool(card_id,returned_at) where claimed_at is null;
create index if not exists cards_catalog_idx on public.cards(is_active,set_id,rarity,card_number);
create unique index if not exists market_active_player_card_idx on public.market_listings(player_card_id) where status='active' and player_card_id is not null;
create index if not exists market_active_idx on public.market_listings(status,listing_type,ends_at,created_at desc);
create index if not exists market_bids_listing_idx on public.market_bids(listing_id,amount desc,created_at desc);
create index if not exists gold_ledger_owner_idx on public.gold_ledger(owner_id,created_at desc);
create index if not exists economy_events_owner_idx on public.economy_events(owner_id,created_at desc);
create index if not exists economy_events_type_idx on public.economy_events(event_type,created_at desc);
create index if not exists economy_events_created_idx on public.economy_events(created_at);
create index if not exists admin_audit_actor_idx on public.admin_audit_log(actor_id,created_at desc);
create index if not exists admin_audit_created_idx on public.admin_audit_log(created_at);
create index if not exists trade_offers_proposer_idx on public.trade_offers(proposer_id,status,created_at desc);
create index if not exists trade_offers_recipient_idx on public.trade_offers(recipient_id,status,created_at desc);
create index if not exists card_fusions_owner_idx on public.card_fusions(owner_id,created_at desc);
create index if not exists player_cards_active_variant_idx on public.player_cards(owner_id,card_id,variant) where retired_at is null;
create index if not exists watchlist_card_target_idx on public.card_watchlist(card_id,variant,target_price);
create index if not exists notifications_owner_unread_idx on public.notifications(owner_id,created_at desc) where read_at is null;
create unique index if not exists notifications_reference_once_idx on public.notifications(owner_id,type,reference_id) where reference_id is not null;
create index if not exists notifications_read_cleanup_idx on public.notifications(read_at,created_at) where read_at is not null;
create index if not exists market_listings_cleanup_idx on public.market_listings(status,updated_at);
create index if not exists market_bids_created_idx on public.market_bids(created_at);
create index if not exists trade_offers_cleanup_idx on public.trade_offers(status,updated_at);
create index if not exists player_cards_retired_cleanup_idx on public.player_cards(retired_at) where retired_at is not null;
create index if not exists system_card_pool_claimed_cleanup_idx on public.system_card_pool(claimed_at) where claimed_at is not null;
create index if not exists daily_claims_date_idx on public.daily_claims(claim_date);
create index if not exists rate_limit_window_idx on public.rate_limit_buckets(window_started_at);

commit;
