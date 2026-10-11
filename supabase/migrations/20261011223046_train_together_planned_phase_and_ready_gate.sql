-- ATHLTH 1.7.3: keep the legacy status contract for installed clients,
-- but record the actual workout lifecycle separately.
-- 'active' in status continues to mean an open social session;
-- workout_phase 'active' means recording has genuinely begun.

alter table public.social_workout_sessions
  add column if not exists workout_phase text not null default 'planned';

alter table public.social_workout_sessions
  drop constraint if exists social_workout_sessions_workout_phase_check;

alter table public.social_workout_sessions
  add constraint social_workout_sessions_workout_phase_check
  check (workout_phase in ('planned', 'active', 'completed', 'cancelled'));

comment on column public.social_workout_sessions.workout_phase is
  'Authoritative exercise lifecycle; separate from legacy social session status.';

-- Safe historical reconciliation: readiness and a countdown alone do not
-- imply a recorded workout.
update public.social_workout_sessions s
set workout_phase = case
  when s.status in ('completed', 'cancelled') then s.status
  when exists (
    select 1
    from public.social_workout_participants p
    where p.session_id = s.id
      and p.workout_started_at is not null
      and p.workout_finished_at is null
  ) then 'active'
  else 'planned'
end
where s.workout_phase is distinct from case
  when s.status in ('completed', 'cancelled') then s.status
  when exists (
    select 1
    from public.social_workout_participants p
    where p.session_id = s.id
      and p.workout_started_at is not null
      and p.workout_finished_at is null
  ) then 'active'
  else 'planned'
end;

create or replace function private.guard_social_workout_phase()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $body$
begin
  if new.status = 'cancelled' then
    new.workout_phase := 'cancelled';
  elsif new.status = 'completed' then
    new.workout_phase := 'completed';
  elsif tg_op = 'INSERT' then
    new.workout_phase := 'planned';
  elsif new.workout_phase = 'active'
        and old.workout_phase is distinct from 'active'
        and not exists (
          select 1
          from public.social_workout_participants p
          where p.session_id = new.id
            and p.workout_started_at is not null
        ) then
    raise exception 'Workout cannot become active before a participant starts';
  elsif new.workout_phase in ('completed', 'cancelled')
        and new.status = 'active' then
    raise exception 'Workout cannot finish while its social session is open';
  end if;

  return new;
end;
$body$;

revoke all on function private.guard_social_workout_phase()
from public, anon, authenticated;

drop trigger if exists social_workout_sessions_workout_phase_guard
on public.social_workout_sessions;

create trigger social_workout_sessions_workout_phase_guard
before insert or update of status, workout_phase
on public.social_workout_sessions
for each row
execute function private.guard_social_workout_phase();

create or replace function private.activate_social_workout_from_recording()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $body$
begin
  if old.workout_started_at is null
     and new.workout_started_at is not null then
    update public.social_workout_sessions
    set workout_phase = 'active',
        updated_at = now()
    where id = new.session_id
      and status = 'active'
      and workout_phase = 'planned';
  end if;
  return new;
end;
$body$;

revoke all on function private.activate_social_workout_from_recording()
from public, anon, authenticated;

drop trigger if exists social_workout_participants_activate_recording
on public.social_workout_participants;

create trigger social_workout_participants_activate_recording
after update of workout_started_at
on public.social_workout_participants
for each row
when (old.workout_started_at is null and new.workout_started_at is not null)
execute function private.activate_social_workout_from_recording();

-- Authorization and readiness validation are enforced INSIDE the RPC,
-- not just by the UI. A session row lock prevents two countdowns; guest
-- row locks stabilize the readiness snapshot until it has been scheduled.
create or replace function public.schedule_social_workout_start(
  p_session_id uuid,
  p_countdown_seconds integer default 3
)
returns timestamptz
language plpgsql
security invoker
set search_path = pg_catalog, public
as $body$
declare
  sess public.social_workout_sessions%rowtype;
  guest_count integer;
  ready_guests integer;
  ready_creator integer;
  started_count integer;
  resolved_start timestamptz;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if p_countdown_seconds is null
     or p_countdown_seconds < 1
     or p_countdown_seconds > 10 then
    raise exception 'Countdown must be between 1 and 10 seconds';
  end if;

  select * into sess
  from public.social_workout_sessions
  where id = p_session_id
  for update;

  if sess.id is null
     or sess.creator_id <> (select auth.uid())
     or sess.status <> 'active' then
    raise exception 'Train Together session is not available';
  end if;

  -- Idempotent retry of an already scheduled start.
  if sess.coordinated_start_at is not null then
    return sess.coordinated_start_at;
  end if;

  if sess.workout_phase <> 'planned'
     or coalesce(sess.invite_payload ->> 'startIndependently', 'false') = 'true' then
    raise exception 'The workout is not waiting for a synchronized start';
  end if;

  perform 1
  from public.social_workout_participants
  where session_id = p_session_id
  for share;

  select
    count(*) filter (
      where p.user_id = sess.creator_id
        and p.state = 'creator'
        and p.ready_at is not null
        and p.capture_device is not null
    ),
    count(*) filter (
      where p.user_id <> sess.creator_id
        and p.state <> 'declined'
    ),
    count(*) filter (
      where p.user_id <> sess.creator_id
        and p.state = 'accepted'
        and p.ready_at is not null
        and p.capture_device is not null
    ),
    count(*) filter (where p.workout_started_at is not null)
  into ready_creator, guest_count, ready_guests, started_count
  from public.social_workout_participants p
  where p.session_id = p_session_id;

  if ready_creator <> 1
     or guest_count < 1
     or guest_count <> ready_guests
     or started_count <> 0 then
    raise exception 'All participants must accept and press Ready before the host can start';
  end if;

  resolved_start := clock_timestamp() + make_interval(secs => p_countdown_seconds);

  update public.social_workout_sessions
  set coordinated_start_at = resolved_start,
      updated_at = now()
  where id = p_session_id
    and status = 'active'
    and workout_phase = 'planned'
    and coordinated_start_at is null;

  if not found then
    raise exception 'The synchronized start could not be scheduled';
  end if;

  return resolved_start;
end;
$body$;

revoke all on function public.schedule_social_workout_start(uuid, integer)
from public, anon;
grant execute on function public.schedule_social_workout_start(uuid, integer)
to authenticated;
