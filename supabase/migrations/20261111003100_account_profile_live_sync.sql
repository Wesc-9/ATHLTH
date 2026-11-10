-- Account-private profile record summaries and invalidation events.
-- Never store HealthKit samples, workout GPS or full exercise logs here.
create schema if not exists athlth_internal;
revoke all on schema athlth_internal from public, anon, authenticated;

create table if not exists public.athlth_profile_record_values (
  user_id uuid not null references public.profiles(id) on delete cascade,
  record_key text not null check (char_length(record_key) between 1 and 100),
  display_value text not null check (char_length(display_value) between 1 and 140),
  supporting_detail text not null default '' check (char_length(supporting_detail) <= 240),
  updated_at timestamptz not null default now(),
  primary key (user_id, record_key)
);
alter table public.athlth_profile_record_values enable row level security;
revoke all on public.athlth_profile_record_values from anon;
grant select, insert, update on public.athlth_profile_record_values to authenticated;
drop policy if exists "Own record summary read" on public.athlth_profile_record_values;
create policy "Own record summary read" on public.athlth_profile_record_values for select to authenticated
  using ((select auth.uid()) = user_id);
drop policy if exists "Own record summary insert" on public.athlth_profile_record_values;
create policy "Own record summary insert" on public.athlth_profile_record_values for insert to authenticated
  with check ((select auth.uid()) = user_id);
drop policy if exists "Own record summary update" on public.athlth_profile_record_values;
create policy "Own record summary update" on public.athlth_profile_record_values for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create table if not exists public.athlth_profile_record_selection (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  selected_kinds text[] not null default '{}'::text[]
    check (cardinality(selected_kinds) <= 4),
  updated_at timestamptz not null default now()
);
alter table public.athlth_profile_record_selection enable row level security;
revoke all on public.athlth_profile_record_selection from anon;
grant select, insert, update on public.athlth_profile_record_selection to authenticated;
drop policy if exists "Own record selection read" on public.athlth_profile_record_selection;
create policy "Own record selection read" on public.athlth_profile_record_selection for select to authenticated
  using ((select auth.uid()) = user_id);
drop policy if exists "Own record selection insert" on public.athlth_profile_record_selection;
create policy "Own record selection insert" on public.athlth_profile_record_selection for insert to authenticated
  with check ((select auth.uid()) = user_id);
drop policy if exists "Own record selection update" on public.athlth_profile_record_selection;
create policy "Own record selection update" on public.athlth_profile_record_selection for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create table if not exists public.athlth_account_sync_events (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  revision bigint not null default 1,
  updated_at timestamptz not null default now()
);
alter table public.athlth_account_sync_events enable row level security;
revoke all on public.athlth_account_sync_events from public, anon, authenticated;
grant select on public.athlth_account_sync_events to authenticated;
drop policy if exists "Own account sync events read" on public.athlth_account_sync_events;
create policy "Own account sync events read" on public.athlth_account_sync_events for select to authenticated
  using ((select auth.uid()) = user_id);

-- All authenticated writes are owner-scoped, and the server owns timestamps.
create or replace function athlth_internal.profile_record_touch()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end
$$;
revoke all on function athlth_internal.profile_record_touch() from public, anon, authenticated;
drop trigger if exists athlth_profile_record_values_touch on public.athlth_profile_record_values;
create trigger athlth_profile_record_values_touch before insert or update on public.athlth_profile_record_values
  for each row execute function athlth_internal.profile_record_touch();
drop trigger if exists athlth_profile_record_selection_touch on public.athlth_profile_record_selection;
create trigger athlth_profile_record_selection_touch before insert or update on public.athlth_profile_record_selection
  for each row execute function athlth_internal.profile_record_touch();

-- Server-only invalidation events: other devices refetch their own authorized data.
-- The events expose neither trophy evidence nor HealthKit-derived numbers.
create or replace function athlth_internal.bump_account_sync_event()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.athlth_account_sync_events(user_id, revision, updated_at)
  values (new.user_id, 1, now())
  on conflict (user_id) do update
    set revision = public.athlth_account_sync_events.revision + 1,
        updated_at = now();
  return new;
end
$$;
revoke all on function athlth_internal.bump_account_sync_event() from public, anon, authenticated;
drop trigger if exists athlth_account_sync_from_awards on public.athlth_award_unlocks;
create trigger athlth_account_sync_from_awards after insert or update on public.athlth_award_unlocks
  for each row execute function athlth_internal.bump_account_sync_event();
drop trigger if exists athlth_account_sync_from_award_preferences on public.user_award_preferences;
create trigger athlth_account_sync_from_award_preferences after insert or update on public.user_award_preferences
  for each row execute function athlth_internal.bump_account_sync_event();
drop trigger if exists athlth_account_sync_from_record_values on public.athlth_profile_record_values;
create trigger athlth_account_sync_from_record_values after insert or update on public.athlth_profile_record_values
  for each row execute function athlth_internal.bump_account_sync_event();
drop trigger if exists athlth_account_sync_from_record_selection on public.athlth_profile_record_selection;
create trigger athlth_account_sync_from_record_selection after insert or update on public.athlth_profile_record_selection
  for each row execute function athlth_internal.bump_account_sync_event();

do $$
begin
 if not exists (
   select 1 from pg_publication_tables
   where pubname = 'supabase_realtime'
     and schemaname = 'public'
     and tablename = 'athlth_account_sync_events'
 ) then
   alter publication supabase_realtime add table public.athlth_account_sync_events;
 end if;
end
$$;
