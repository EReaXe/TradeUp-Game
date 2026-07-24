begin;

create table if not exists public.player_card_discoveries(
  owner_id uuid not null references public.profiles(id) on delete cascade,
  card_id uuid not null references public.cards(id) on delete cascade,
  first_discovered_at timestamptz not null default now(),
  last_acquired_at timestamptz not null default now(),
  primary key(owner_id,card_id)
);

create or replace function public.record_player_card_discovery()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  insert into public.player_card_discoveries(
    owner_id,card_id,first_discovered_at,last_acquired_at
  )
  values(
    new.owner_id,new.card_id,coalesce(new.obtained_at,now()),coalesce(new.obtained_at,now())
  )
  on conflict(owner_id,card_id) do update
  set last_acquired_at=greatest(
    public.player_card_discoveries.last_acquired_at,
    excluded.last_acquired_at
  );
  return new;
end
$$;

drop trigger if exists player_card_discovery_tracker on public.player_cards;
create trigger player_card_discovery_tracker
after insert or update of owner_id on public.player_cards
for each row execute function public.record_player_card_discovery();

-- Restore as much discovery history as the existing operational records retain.
insert into public.player_card_discoveries(owner_id,card_id,first_discovered_at,last_acquired_at)
select owner_id,card_id,min(obtained_at),max(obtained_at)
from public.player_cards
group by owner_id,card_id
on conflict(owner_id,card_id) do update
set first_discovered_at=least(player_card_discoveries.first_discovered_at,excluded.first_discovered_at),
    last_acquired_at=greatest(player_card_discoveries.last_acquired_at,excluded.last_acquired_at);

insert into public.player_card_discoveries(owner_id,card_id,first_discovered_at,last_acquired_at)
select seller_id,card_id,min(created_at),max(created_at)
from public.market_listings
where seller_id is not null
group by seller_id,card_id
on conflict(owner_id,card_id) do nothing;

insert into public.player_card_discoveries(owner_id,card_id,first_discovered_at,last_acquired_at)
select returned_by,card_id,min(returned_at),max(returned_at)
from public.system_card_pool
where returned_by is not null
group by returned_by,card_id
on conflict(owner_id,card_id) do nothing;

insert into public.player_card_discoveries(owner_id,card_id,first_discovered_at,last_acquired_at)
select i.owner_id,pc.card_id,min(t.created_at),max(t.created_at)
from public.trade_offer_items i
join public.trade_offers t on t.id=i.trade_id
join public.player_cards pc on pc.id=i.player_card_id
group by i.owner_id,pc.card_id
on conflict(owner_id,card_id) do nothing;

insert into public.player_card_discoveries(owner_id,card_id,first_discovered_at,last_acquired_at)
select owner_id,card_id,min(created_at),max(created_at)
from public.card_fusions
group by owner_id,card_id
on conflict(owner_id,card_id) do nothing;

alter table public.player_card_discoveries enable row level security;
drop policy if exists player_card_discoveries_owner_read on public.player_card_discoveries;
create policy player_card_discoveries_owner_read
on public.player_card_discoveries for select to authenticated
using(auth.uid()=owner_id);

revoke all on public.player_card_discoveries from anon,authenticated;
grant select on public.player_card_discoveries to authenticated;
revoke all on function public.record_player_card_discovery() from public,anon,authenticated;

commit;
