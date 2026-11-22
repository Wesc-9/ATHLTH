-- Server-authoritative approval gate: a modified plan cannot be launched
-- by an old client or by a stale owner-side calendar snapshot.
create or replace function private.guard_train_together_live_draft_start()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_source uuid;
  v_draft public.social_workout_draft_lobbies%rowtype;
  v_payload jsonb;
  v_snapshot jsonb;
begin
  if old.coordinated_start_at is not null
     or new.coordinated_start_at is null then
    return new;
  end if;

  if new.invite_payload is null
     or new.invite_payload #>> '{workout,id}' is null then
    return new;
  end if;

  v_source := (new.invite_payload #>> '{workout,id}')::uuid;
  select * into v_draft
    from public.social_workout_draft_lobbies
    where source_workout_id = v_source
    for share;
  -- Previous app versions have no shared draft and retain their legacy start.
  if not found then return new; end if;

  if v_draft.owner_id <> new.creator_id
     or v_draft.owner_approved_revision is distinct from v_draft.revision
     or v_draft.partner_approved_revision is distinct from v_draft.revision then
    raise exception 'Both partners must approve the current workout before start';
  end if;

  if not exists (
    select 1 from public.social_workout_participants p
    where p.session_id = new.id
      and p.user_id = v_draft.partner_id
      and p.state = 'accepted'
  ) then
    raise exception 'The approved training partner has not joined';
  end if;

  if (new.invite_payload ->> 'participationMode') is distinct from
       v_draft.participation_mode then
    raise exception 'Training location differs from the approved draft';
  end if;

  v_payload := (new.invite_payload->'workout')
      - 'gearIDs' - 'spotifyPlaylist' - 'spotifyAutoplayOnStart';
  v_snapshot := (v_draft.workout_snapshot::jsonb)
      - 'gearIDs' - 'spotifyPlaylist' - 'spotifyAutoplayOnStart';
  if v_payload is distinct from v_snapshot then
    raise exception 'Start requires the latest approved workout revision';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_train_together_live_draft_start()
 from public, anon, authenticated;

drop trigger if exists guard_train_together_live_draft_start
 on public.social_workout_sessions;
create trigger guard_train_together_live_draft_start
before update of coordinated_start_at
on public.social_workout_sessions
for each row
execute function private.guard_train_together_live_draft_start();

-- Once a recorded workout has started, a subsequent edit is a new workout;
-- it must not silently mutate the agreed workout already in progress.
create or replace function private.guard_train_together_live_draft_edit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if new.workout_snapshot is distinct from old.workout_snapshot
    and exists (
      select 1
      from public.social_workout_sessions s
      where s.invite_payload #>> '{workout,id}'
         = old.source_workout_id::text
        and s.coordinated_start_at is not null
    ) then
    raise exception 'This workout has already started and cannot be edited';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_train_together_live_draft_edit()
 from public, anon, authenticated;

drop trigger if exists guard_train_together_live_draft_edit
 on public.social_workout_draft_lobbies;
create trigger guard_train_together_live_draft_edit
before update of workout_snapshot
on public.social_workout_draft_lobbies
for each row
execute function private.guard_train_together_live_draft_edit();
