create or replace function public.begin_ghost_live_session(
  p_challenge_id uuid
)
returns public.live_workout_sessions
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

  select *
  into challenge
  from public.ghost_race_challenges
  where id = p_challenge_id;

  if not found
     or challenge.status <> 'accepted'
     or challenge.expires_at <= now()
     or actor not in (challenge.sender_id, challenge.recipient_id) then
    raise exception 'Ghost Race is not available for live start';
  end if;

  select *
  into existing
  from public.live_workout_sessions
  where ghost_challenge_id = p_challenge_id
    and status in ('active','paused')
  order by started_at desc
  limit 1;

  if found then
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
  )
  values (
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
  )
  returning * into created;

  return created;
end;
$function$;
