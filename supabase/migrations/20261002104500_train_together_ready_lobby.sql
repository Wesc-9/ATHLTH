-- Train Together ready lobby and independent participant lifecycle.
-- The shared session carries only coordination state; each participant keeps
-- their own HealthKit/workout session and can finish independently.

alter table public.social_workout_sessions
  add column if not exists coordinated_start_at timestamptz;

alter table public.social_workout_participants
  add column if not exists ready_at timestamptz,
  add column if not exists capture_device text,
  add column if not exists workout_started_at timestamptz,
  add column if not exists workout_finished_at timestamptz;

alter table public.social_workout_participants
  drop constraint if exists social_workout_participants_capture_device_check;

alter table public.social_workout_participants
  add constraint social_workout_participants_capture_device_check
  check (
    capture_device is null
    or capture_device in ('iphone','apple_watch')
  );

create or replace function private.guard_social_workout_participant()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  creator uuid;
  scheduled_start timestamptz;
begin
  select s.creator_id, s.coordinated_start_at
    into creator, scheduled_start
  from public.social_workout_sessions s
  where s.id = coalesce(new.session_id, old.session_id);

  if creator is null then
    raise exception 'Workout session not found';
  end if;

  if tg_op = 'INSERT' then
    if actor <> creator or new.invited_by <> actor then
      raise exception 'Only the workout creator can add participants';
    end if;

    if new.user_id = creator then
      if new.state <> 'creator' then
        raise exception 'Workout creator must use creator state';
      end if;
      return new;
    end if;

    if new.state <> 'invited' then
      raise exception 'New workout participants must start as invited';
    end if;

    if not private.are_friends(new.user_id) then
      raise exception 'Workout participants must already be friends';
    end if;

    if private.is_blocked(new.user_id) then
      raise exception 'Workout invitation is not available for this user';
    end if;

    return new;
  end if;

  if new.id <> old.id
     or new.session_id <> old.session_id
     or new.user_id <> old.user_id
     or new.invited_by <> old.invited_by
     or new.invited_at <> old.invited_at
     or new.display_name_snapshot <> old.display_name_snapshot
     or new.username_snapshot is distinct from old.username_snapshot then
    raise exception 'Workout participant identity fields are immutable';
  end if;

  if actor <> old.user_id then
    raise exception 'Participants can only update their own workout state';
  end if;

  if new.state <> old.state then
    if old.state <> 'invited'
       or new.state not in ('accepted','declined') then
      raise exception 'Invalid workout invitation transition';
    end if;

    if new.ready_at is distinct from old.ready_at
       or new.capture_device is distinct from old.capture_device
       or new.workout_started_at is distinct from old.workout_started_at
       or new.workout_finished_at is distinct from old.workout_finished_at then
      raise exception 'Accept or decline the invitation before changing workout readiness';
    end if;

    new.responded_at := now();
    return new;
  end if;

  if old.state not in ('creator','accepted') then
    raise exception 'Only accepted participants can update workout readiness';
  end if;

  if new.responded_at is distinct from old.responded_at then
    raise exception 'Workout response timestamp is immutable';
  end if;

  if new.ready_at is not null and new.capture_device is null then
    raise exception 'A ready participant must choose a workout device';
  end if;

  if old.workout_started_at is not null
     and new.capture_device is distinct from old.capture_device then
    raise exception 'Workout device cannot change after the workout starts';
  end if;

  if new.workout_started_at is not null then
    if new.ready_at is null then
      raise exception 'Participant must be ready before starting';
    end if;
    if scheduled_start is null then
      raise exception 'Shared workout has not been started by the creator';
    end if;
  end if;

  if new.workout_finished_at is not null
     and new.workout_started_at is null then
    raise exception 'Workout cannot finish before it starts';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_social_workout_participant()
from public, anon, authenticated;

create or replace function private.social_workout_coordinated_start_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if old.coordinated_start_at is null
     and new.coordinated_start_at is not null then
    insert into public.social_inbox_events (
      recipient_id, kind, title, message, entity_type, entity_id
    )
    select
      p.user_id,
      'workout_invite_accepted',
      'Workout starting',
      'Your Train Together workout starts now.',
      'workout_session',
      new.id
    from public.social_workout_participants p
    where p.session_id = new.id
      and p.user_id <> new.creator_id
      and p.state = 'accepted';
  end if;

  return new;
end;
$$;

revoke all on function private.social_workout_coordinated_start_event()
from public, anon, authenticated;

drop trigger if exists social_workout_sessions_coordinated_start_event
on public.social_workout_sessions;

create trigger social_workout_sessions_coordinated_start_event
after update of coordinated_start_at on public.social_workout_sessions
for each row
execute function private.social_workout_coordinated_start_event();

create or replace function private.complete_social_workout_when_group_done()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if old.workout_finished_at is null
     and new.workout_finished_at is not null then
    update public.social_workout_sessions s
    set
      status = 'completed',
      ended_at = coalesce(s.ended_at, now()),
      updated_at = now()
    where s.id = new.session_id
      and s.status = 'active'
      and exists (
        select 1
        from public.social_workout_participants p
        where p.session_id = s.id
          and p.state in ('creator','accepted')
          and p.ready_at is not null
      )
      and not exists (
        select 1
        from public.social_workout_participants p
        where p.session_id = s.id
          and p.state in ('creator','accepted')
          and p.ready_at is not null
          and p.workout_finished_at is null
      );
  end if;

  return new;
end;
$$;

revoke all on function private.complete_social_workout_when_group_done()
from public, anon, authenticated;

drop trigger if exists social_workout_participants_group_done
on public.social_workout_participants;

create trigger social_workout_participants_group_done
after update of workout_finished_at on public.social_workout_participants
for each row
execute function private.complete_social_workout_when_group_done();
