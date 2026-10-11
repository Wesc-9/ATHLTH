-- Explicit cancellation/DNF for a synchronized Live Ghost duel.
-- Cancelling never fabricates a winning time, settles Arena points, or stops
-- the user's local HealthKit workout. Existing finished races are immutable.
create or replace function private.live_ghost_preserve_terminal_room()
returns trigger language plpgsql
set search_path = pg_catalog, public, private
as $$
begin
  if old.status in ('finished','cancelled')
     and new.status is distinct from old.status then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists live_ghost_preserve_terminal_room
  on public.live_ghost_race_rooms;
create trigger live_ghost_preserve_terminal_room
before update of status on public.live_ghost_race_rooms
for each row execute function private.live_ghost_preserve_terminal_room();

create or replace function public.cancel_live_ghost_duel(
  p_challenge_id uuid
) returns boolean
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  race public.ghost_race_challenges%rowtype;
  room public.live_ghost_race_rooms%rowtype;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;
  if p_challenge_id is null then
    raise exception 'Challenge is required';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_challenge_id::text));

  select * into race
  from public.ghost_race_challenges
  where id = p_challenge_id;

  if not found
     or race.status <> 'accepted'
     or actor not in (race.sender_id, race.recipient_id) then
    raise exception 'Live Ghost duel is unavailable';
  end if;

  select * into room from public.live_ghost_race_rooms
  where challenge_id = p_challenge_id for update;

  if not found or room.status in ('finished','cancelled') then
    return false;
  end if;

  update public.live_ghost_race_rooms
  set status = 'cancelled',
      finished_at = coalesce(finished_at, now()),
      winner_id = null,
      updated_at = now()
  where challenge_id = p_challenge_id
    and status in ('lobby','countdown','racing');

  -- This ends only the shared live session, never the phone/Watch recording.
  update public.live_workout_sessions
  set status = 'cancelled',
      ended_at = greatest(now(), started_at),
      updated_at = now()
  where ghost_challenge_id = p_challenge_id
    and status in ('active','paused');

  return true;
end;
$$;

revoke all on function public.cancel_live_ghost_duel(uuid)
  from public, anon;
grant execute on function public.cancel_live_ghost_duel(uuid)
  to authenticated;

comment on function public.cancel_live_ghost_duel(uuid) is
  'Participant-authorized cancellation of shared Live Ghost only; never grants Arena points or ends local HealthKit workouts.';
