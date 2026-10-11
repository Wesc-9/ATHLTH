-- ATHLTH 1.7.3: protect coordinated_start_at even from direct row updates.
-- Creator-only starts require explicit readiness; independent starts use a
-- separate creator-authorized RPC and do not launch invited athletes.

create or replace function private.guard_social_workout_start_schedule()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $body$
declare
  guest_count integer;
  ready_guests integer;
  ready_creator integer;
  independent_start boolean;
begin
  if new.coordinated_start_at is not distinct from old.coordinated_start_at then
    return new;
  end if;

  if old.coordinated_start_at is not null
     or new.coordinated_start_at is null
     or new.creator_id <> (select auth.uid())
     or new.status <> 'active'
     or new.workout_phase <> 'planned' then
    raise exception 'Workout start cannot be modified';
  end if;

  -- Scheduling can only be immediate or a short (up to 10s) countdown.
  if new.coordinated_start_at < clock_timestamp() - interval '1 second'
     or new.coordinated_start_at > clock_timestamp() + interval '11 seconds' then
    raise exception 'Invalid workout start time';
  end if;

  perform 1
  from public.social_workout_participants p
  where p.session_id = new.id
  for share;

  select
    count(*) filter (
      where p.user_id = new.creator_id
        and p.state = 'creator'
        and p.ready_at is not null
        and p.capture_device is not null
    ),
    count(*) filter (
      where p.user_id <> new.creator_id and p.state <> 'declined'
    ),
    count(*) filter (
      where p.user_id <> new.creator_id
        and p.state = 'accepted'
        and p.ready_at is not null
        and p.capture_device is not null
    )
  into ready_creator, guest_count, ready_guests
  from public.social_workout_participants p
  where p.session_id = new.id;

  if ready_creator <> 1 then
    raise exception 'The workout creator must press Ready first';
  end if;

  independent_start :=
    coalesce(new.invite_payload ->> 'startIndependently', 'false') = 'true';

  if not independent_start
     and (guest_count < 1 or guest_count <> ready_guests) then
    raise exception 'All invited participants must accept and press Ready first';
  end if;

  return new;
end;
$body$;

revoke all on function private.guard_social_workout_start_schedule()
from public, anon, authenticated;

drop trigger if exists social_workout_sessions_start_schedule_guard
on public.social_workout_sessions;

create trigger social_workout_sessions_start_schedule_guard
before update of coordinated_start_at
on public.social_workout_sessions
for each row
execute function private.guard_social_workout_start_schedule();

create or replace function public.schedule_social_workout_independent_start(
  p_session_id uuid
)
returns timestamptz
language plpgsql
security invoker
set search_path = pg_catalog, public
as $body$
declare
  sess public.social_workout_sessions%rowtype;
  resolved_start timestamptz;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select * into sess
  from public.social_workout_sessions
  where id = p_session_id
  for update;

  if sess.id is null
     or sess.creator_id <> (select auth.uid())
     or sess.status <> 'active'
     or sess.workout_phase <> 'planned'
     or coalesce(sess.invite_payload ->> 'startIndependently', 'false') <> 'true'
  then
    raise exception 'An independent start is not available';
  end if;

  if sess.coordinated_start_at is not null then
    return sess.coordinated_start_at;
  end if;

  resolved_start := clock_timestamp();
  -- The start schedule guard additionally verifies creator readiness.
  update public.social_workout_sessions
  set coordinated_start_at = resolved_start,
      updated_at = now()
  where id = p_session_id
    and status = 'active'
    and workout_phase = 'planned'
    and coordinated_start_at is null;

  if not found then
    raise exception 'The independent workout could not be started';
  end if;

  return resolved_start;
end;
$body$;

revoke all on function public.schedule_social_workout_independent_start(uuid)
from public, anon;
grant execute on function public.schedule_social_workout_independent_start(uuid)
to authenticated;
