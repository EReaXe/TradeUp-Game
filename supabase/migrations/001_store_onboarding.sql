-- Phase 1 only: authenticated store identity. No economic fields.
begin;
create table if not exists public.store_onboarding (
 user_id uuid primary key references auth.users(id) on delete cascade,
 username text not null check (username ~ '^[a-zA-Z0-9_]{3,24}$'),
 store_name text not null check (char_length(store_name) between 3 and 40 and store_name = btrim(store_name)),
 created_at timestamptz not null default now()
);
create unique index if not exists store_onboarding_username_unique on public.store_onboarding(lower(username));
create unique index if not exists store_onboarding_name_unique on public.store_onboarding(lower(store_name));
alter table public.store_onboarding enable row level security;
revoke all on public.store_onboarding from public, anon, authenticated;
grant select on public.store_onboarding to authenticated;
drop policy if exists onboarding_select_own on public.store_onboarding;
create policy onboarding_select_own on public.store_onboarding for select to authenticated using ((select auth.uid()) = user_id);
create or replace function public.complete_store_onboarding(p_username text,p_store_name text)
returns public.store_onboarding language plpgsql security definer set search_path = '' as $$
declare
 v_user uuid := auth.uid();
 v_row public.store_onboarding;
begin
 if v_user is null then raise exception 'Authentication required' using errcode='28000'; end if;
 -- Retries and concurrent requests from one user return the existing identity.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text,0));
 select * into v_row from public.store_onboarding where user_id=v_user;
 if found then return v_row; end if;
 if p_username is null or p_username !~ '^[a-zA-Z0-9_]{3,24}$'
 or p_store_name is null or char_length(btrim(p_store_name)) not between 3 and 40
 then raise exception 'Invalid store identity' using errcode='22023'; end if;
 insert into public.store_onboarding(user_id,username,store_name)
 values(v_user,p_username,btrim(p_store_name)) returning * into v_row;
 return v_row;
end;
$$;
revoke all on function public.complete_store_onboarding(text,text) from public,anon,authenticated;
grant execute on function public.complete_store_onboarding(text,text) to authenticated;
commit;
