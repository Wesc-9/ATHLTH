-- Protect Live Ghost sessions from premature location sharing.
-- This gate is enforced by the backend, not just by the iPhone/Watch UI.
-- A legitimate race remains reconnectable after invitation expiry while
-- finished/cancelled duels remain terminal.

create or replace function private.live_ghost_shared_start_allowed(
  p_challenge_id uuid
) returns boolean
language sql stable security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
  select exists (
    select 1
    from public.live_ghost_race_rooms room
    join public.ghost_race_challenges challenge
      on challenge.id = room.challenge_id
    where room.challenge_id = p_challenge_id
      and challenge.status = 'accepted'
      and (
        room.status = 'racing'
        or (
          room.status = 'countdown'
          and room.starts_at is not null
          and room.starts_at <= now()
          and exists (
            select 1
            from public.live_ghost_race_participants sender
            where sender.challenge_id = p_challenge_id
              and sender.user_id = challenge.sender_id
              and sender.ready is true
          )
          and exists (
            select 1
            from public.live_ghost_race_participants recipient
            where recipient.challenge_id = p_challenge_id
              and recipient.user_id = challenge.recipient_id
              and recipient.ready is true
          )
        )
      )
  );
$$;

revoke all on function private.live_ghost_shared_start_allowed(uuid)
  from public, anon, authenticated;

-- Reconnecting an already-started Live Ghost must survive invitation expiry.
-- Expiry still blocks creation of a NEW live workout session.
-- Only the two accepted athletes may access an existing active shared session.
create or replace function public.begin_ghost_live_session(
  p_challenge_id uuid
) returns public.live_workout_sessions
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  actor uuid := (select auth.uid());
  challenge public.ghost_race_challenges%rowtype;
  existing public.live_workout_sessions%rowtype;
  created public.live_workout_sessions%rowtype;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_challenge_id::text));

  select * into challenge
  from public.ghost_race_challenges
  where id = p_challenge_id;

  if not found
     or challenge.status <> 'accepted'
     or actor not in (challenge.sender_id, challenge.recipient_id) then
    raise exception 'Ghost Race is not available for live start';
  end if;

  select * into existing
  from public.live_workout_sessions
  where ghost_challenge_id = p_challenge_id
    and status in ('active', 'paused')
  order by started_at desc
  limit 1;

  -- A finished or cancelled room must never spawn or revive a live session.
  if exists (
    select 1 from public.live_ghost_race_rooms r
    where r.challenge_id = p_challenge_id
      and r.status in ('finished', 'cancelled')
  ) then
    raise exception 'Live Ghost has already ended';
  end if;

  -- The shared location stream may only be connected after the server
  -- has committed a synchronized race start. The room's status sometimes
  -- remains 'countdown' briefly after starts_at until a readiness update;
  -- accept that case only when BOTH authorized athletes remain ready.
  if not private.live_ghost_shared_start_allowed(p_challenge_id) then
    raise exception 'Synchronized Live Ghost race has not started';
  end if;

  -- Expiry applies to STARTING a race, not reconnecting to a shared session
  -- that was created before expiry and whose countdown/race is underway.
  if challenge.expires_at <= now()
     and (
       existing.id is null
       or not exists (
         select 1 from public.live_ghost_race_rooms r
         where r.challenge_id = p_challenge_id
           and r.status in ('countdown', 'racing')
       )
     ) then
    raise exception 'Expired Live Ghost cannot start a new workout';
  end if;

  if existing.id is not null then
    update public.live_workout_sessions
    set route_key = coalesce(existing.route_key, challenge.id),
        route_distance_meters =
          coalesce(existing.route_distance_meters, challenge.distance_meters),
        route_title = coalesce(existing.route_title, challenge.title),
        updated_at = now()
    where id = existing.id
    returning * into existing;

    return existing;
  end if;

  insert into public.live_workout_sessions (
    owner_id,
    opponent_user_id,
    ghost_challenge_id,
    activity,
    title,
    visibility,
    status,
    route_key,
    route_distance_meters,
    route_title
  ) values (
    challenge.sender_id,
    challenge.recipient_id,
    challenge.id,
    'running',
    challenge.title,
    'private',
    'active',
    challenge.id,
    challenge.distance_meters,
    challenge.title
  ) returning * into created;

  return created;
end;
$function$;

revoke all on function public.begin_ghost_live_session(uuid)
  from public, anon;
grant execute on function public.begin_ghost_live_session(uuid)
  to authenticated;
