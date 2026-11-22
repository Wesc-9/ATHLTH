-- Live, revisioned planning for every PlannedSession workout kind.
-- No workout/HealthKit session is created or started by these RPCs.
create table if not exists public.social_workout_draft_lobbies (
  source_workout_id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid not null references auth.users(id) on delete cascade,
  edit_mode text not null check (edit_mode in ('collaborative', 'view_only')),
  participation_mode text not null check (participation_mode in ('physical', 'remote')),
  workout_snapshot text not null,
  revision integer not null default 1 check (revision > 0),
  owner_approved_revision integer,
  partner_approved_revision integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint social_workout_draft_distinct_users check (owner_id <> partner_id),
  constraint social_workout_draft_size check (octet_length(workout_snapshot) between 2 and 524288)
);
create index if not exists social_workout_draft_partner_idx
  on public.social_workout_draft_lobbies(partner_id, updated_at desc);
alter table public.social_workout_draft_lobbies enable row level security;
revoke all on public.social_workout_draft_lobbies from public, anon;
revoke insert, update, delete on public.social_workout_draft_lobbies from authenticated;
grant select on public.social_workout_draft_lobbies to authenticated;

drop policy if exists social_workout_draft_members_read on public.social_workout_draft_lobbies;
create policy social_workout_draft_members_read
  on public.social_workout_draft_lobbies for select to authenticated
  using ((select auth.uid()) in (owner_id, partner_id));

-- Creation is idempotent; retrying an invitation must not overwrite a newer
-- revision or create a second lobby. Privileges never derive from user metadata.
create or replace function public.create_social_workout_draft(
  p_source_id uuid, p_partner_id uuid, p_edit_mode text,
  p_participation_mode text, p_snapshot text
) returns public.social_workout_draft_lobbies
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := (select auth.uid());
  v_existing public.social_workout_draft_lobbies;
  v_json jsonb;
begin
  if v_actor is null or p_partner_id is null or p_partner_id = v_actor then
    raise exception 'Invalid training partner';
  end if;
  if p_edit_mode not in ('collaborative','view_only')
     or p_participation_mode not in ('physical','remote') then
    raise exception 'Invalid Train Together mode';
  end if;
  if not private.are_friends(p_partner_id)
     or private.is_blocked(p_partner_id) then
    raise exception 'Train Together requires a mutual, unblocked friend';
  end if;
  if octet_length(p_snapshot) > 524288 then
    raise exception 'Workout exceeds allowed size';
  end if;
  v_json := p_snapshot::jsonb;
  if jsonb_typeof(v_json) <> 'object'
     or (v_json->>'id')::uuid is distinct from p_source_id
     or coalesce(v_json->>'kind','') = '' then
    raise exception 'Invalid workout snapshot';
  end if;
  insert into public.social_workout_draft_lobbies (
    source_workout_id,owner_id,partner_id,edit_mode,participation_mode,workout_snapshot
  ) values (
    p_source_id,v_actor,p_partner_id,p_edit_mode,p_participation_mode,p_snapshot
  ) on conflict (source_workout_id) do nothing;
  select * into v_existing from public.social_workout_draft_lobbies
    where source_workout_id = p_source_id;
  if v_existing.owner_id <> v_actor or v_existing.partner_id <> p_partner_id
     or v_existing.edit_mode <> p_edit_mode
     or v_existing.participation_mode <> p_participation_mode then
    raise exception 'This workout already belongs to another invitation';
  end if;
  return v_existing;
end;
$$;

-- Optimistic compare-and-swap: simultaneous edits never silently overwrite.
-- An edit invalidates BOTH approvals. Guest edits cannot escalate permissions
-- or replace the source identity/organizer preferences.
create or replace function public.update_social_workout_draft(
  p_source_id uuid, p_expected_revision integer, p_snapshot text
) returns public.social_workout_draft_lobbies
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := (select auth.uid());
  v_row public.social_workout_draft_lobbies;
  v_old jsonb;
  v_new jsonb;
begin
  select * into v_row from public.social_workout_draft_lobbies
    where source_workout_id = p_source_id for update;
  if not found or v_actor is null
     or v_actor not in (v_row.owner_id, v_row.partner_id) then
    raise exception 'Workout draft unavailable';
  end if;
  if v_actor = v_row.partner_id and v_row.edit_mode <> 'collaborative' then
    raise exception 'This workout is read-only for invitees';
  end if;
  if v_row.revision <> p_expected_revision then
    raise exception 'Workout changed. Refresh before editing again';
  end if;
  if octet_length(p_snapshot) > 524288 then
    raise exception 'Workout exceeds allowed size';
  end if;
  v_old := v_row.workout_snapshot::jsonb;
  v_new := p_snapshot::jsonb;
  if jsonb_typeof(v_new) <> 'object'
     or (v_new->>'id')::uuid is distinct from p_source_id
     or v_new->>'kind' is distinct from v_old->>'kind' then
    raise exception 'Workout identity or training mode cannot change during collaboration';
  end if;
  if v_actor = v_row.partner_id and (
    (v_new->>'invitedPartnerID') is distinct from (v_old->>'invitedPartnerID')
    or (v_new->>'allowInviteeExercises') is distinct from (v_old->>'allowInviteeExercises')
    or (v_new->>'trainTogetherMode') is distinct from (v_old->>'trainTogetherMode')
    or (v_new->'gearIDs') is distinct from (v_old->'gearIDs')
    or (v_new->'spotifyPlaylist') is distinct from (v_old->'spotifyPlaylist')
    or (v_new->'spotifyAutoplayOnStart') is distinct from (v_old->'spotifyAutoplayOnStart')
  ) then
    raise exception 'Participant cannot change organizer-only settings';
  end if;
  if v_new = v_old then return v_row; end if;
  update public.social_workout_draft_lobbies set
    workout_snapshot = p_snapshot,
    revision = revision + 1,
    owner_approved_revision = null,
    partner_approved_revision = null,
    updated_at = now()
  where source_workout_id = p_source_id
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.approve_social_workout_draft(
  p_source_id uuid, p_expected_revision integer
) returns public.social_workout_draft_lobbies
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := (select auth.uid());
  v_row public.social_workout_draft_lobbies;
begin
  select * into v_row from public.social_workout_draft_lobbies
    where source_workout_id = p_source_id for update;
  if not found or v_actor is null
     or v_actor not in (v_row.owner_id,v_row.partner_id) then
    raise exception 'Workout draft unavailable';
  end if;
  if v_row.revision <> p_expected_revision then
    raise exception 'Workout changed. Review the new version before approving';
  end if;
  update public.social_workout_draft_lobbies set
    owner_approved_revision = case when v_actor = owner_id then revision else owner_approved_revision end,
    partner_approved_revision = case when v_actor = partner_id then revision else partner_approved_revision end,
    updated_at = now()
  where source_workout_id = p_source_id returning * into v_row;
  return v_row;
end;
$$;

revoke all on function public.create_social_workout_draft(uuid,uuid,text,text,text)
 from public, anon;
revoke all on function public.update_social_workout_draft(uuid,integer,text)
 from public, anon;
revoke all on function public.approve_social_workout_draft(uuid,integer)
 from public, anon;
grant execute on function public.create_social_workout_draft(uuid,uuid,text,text,text) to authenticated;
grant execute on function public.update_social_workout_draft(uuid,integer,text) to authenticated;
grant execute on function public.approve_social_workout_draft(uuid,integer) to authenticated;

-- Publication membership supports Supabase Postgres Changes subscriptions.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'social_workout_draft_lobbies'
  ) then
    alter publication supabase_realtime add table public.social_workout_draft_lobbies;
  end if;
end $$;
