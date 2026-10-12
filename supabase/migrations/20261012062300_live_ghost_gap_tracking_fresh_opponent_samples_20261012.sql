-- Arena 1.7.3 phase 3: compare fresh synchronized samples before recording permanent lead changes.
-- No GPS trace, competition scoring or historical result is modified.
CREATE OR REPLACE FUNCTION private.track_live_ghost_race_gap()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  session_row public.live_workout_sessions%rowtype;
  challenge_row public.ghost_race_challenges%rowtype;
  sender_location public.live_workout_locations%rowtype;
  recipient_location public.live_workout_locations%rowtype;
  room_row public.live_ghost_race_rooms%rowtype;
  signed_gap double precision;
  next_leader uuid;
  changes integer := 0;
  sender_best double precision;
  recipient_best double precision;
  sender_improved boolean := false;
  recipient_improved boolean := false;
begin
  select * into session_row
  from public.live_workout_sessions
  where id = new.session_id
    and ghost_challenge_id is not null;

  if not found then
    return new;
  end if;

  select * into challenge_row
  from public.ghost_race_challenges
  where id = session_row.ghost_challenge_id;

  if not found then
    return new;
  end if;

  select * into sender_location
  from public.live_workout_locations
  where session_id = new.session_id
    and user_id = challenge_row.sender_id;

  select * into recipient_location
  from public.live_workout_locations
  where session_id = new.session_id
    and user_id = challenge_row.recipient_id;

  if sender_location.user_id is null
     or recipient_location.user_id is null then
    return new;
  end if;

  select * into room_row
  from public.live_ghost_race_rooms
  where challenge_id = challenge_row.id
  for update;

  if not found then
    return new;
  end if;

  -- Only live race and plausible, fresh position of both runners count.
  if room_row.status not in ('countdown','racing')
     or room_row.starts_at is null
     or room_row.starts_at > clock_timestamp()
     or new.user_id not in (challenge_row.sender_id, challenge_row.recipient_id)
     or sender_location.expires_at <= clock_timestamp()
     or sender_location.updated_at < clock_timestamp() - interval '18 seconds'
     or sender_location.updated_at > clock_timestamp() + interval '5 seconds'
     or sender_location.elapsed_seconds is null
     or sender_location.elapsed_seconds < 0
     or sender_location.elapsed_seconds > 86400
     or sender_location.distance_meters is null
     or sender_location.distance_meters < 0
     or sender_location.distance_meters > greatest(120, sender_location.elapsed_seconds * 15)
     or (sender_location.horizontal_accuracy is not null and (sender_location.horizontal_accuracy < 0 or sender_location.horizontal_accuracy > 50))
     or recipient_location.expires_at <= clock_timestamp()
     or recipient_location.updated_at < clock_timestamp() - interval '18 seconds'
     or recipient_location.updated_at > clock_timestamp() + interval '5 seconds'
     or recipient_location.elapsed_seconds is null
     or recipient_location.elapsed_seconds < 0
     or recipient_location.elapsed_seconds > 86400
     or recipient_location.distance_meters is null
     or recipient_location.distance_meters < 0
     or recipient_location.distance_meters > greatest(120, recipient_location.elapsed_seconds * 15)
     or (recipient_location.horizontal_accuracy is not null and (recipient_location.horizontal_accuracy < 0 or recipient_location.horizontal_accuracy > 50)) then
    return new;
  end if;

  if sender_location.route_progress_percent between 0 and 100
     and recipient_location.route_progress_percent between 0 and 100
     and session_row.route_distance_meters between 250 and 500000
     and (sender_location.route_deviation_meters is null or sender_location.route_deviation_meters between 0 and 120)
     and (recipient_location.route_deviation_meters is null or recipient_location.route_deviation_meters between 0 and 120) then
    signed_gap := (sender_location.route_progress_percent - recipient_location.route_progress_percent) / 100.0 * session_row.route_distance_meters;
  else
    signed_gap := sender_location.distance_meters - recipient_location.distance_meters;
  end if;

  sender_best :=
    greatest(room_row.sender_max_lead_meters, signed_gap, 0);
  recipient_best :=
    greatest(room_row.recipient_max_lead_meters, -signed_gap, 0);

  sender_improved :=
    sender_best >= room_row.sender_max_lead_meters + 3;
  recipient_improved :=
    recipient_best >= room_row.recipient_max_lead_meters + 3;

  if signed_gap >= 8 then
    next_leader := challenge_row.sender_id;
  elsif signed_gap <= -8 then
    next_leader := challenge_row.recipient_id;
  else
    next_leader := room_row.last_leader_id;
  end if;

  if next_leader is not null
     and room_row.last_leader_id is not null
     and next_leader <> room_row.last_leader_id then
    changes := 1;
  end if;

  if sender_improved
     or recipient_improved
     or changes > 0
     or (
       next_leader is distinct from room_row.last_leader_id
       and next_leader is not null
     ) then
    update public.live_ghost_race_rooms
    set sender_max_lead_meters =
          case when sender_improved
               then sender_best
               else sender_max_lead_meters end,
        recipient_max_lead_meters =
          case when recipient_improved
               then recipient_best
               else recipient_max_lead_meters end,
        lead_change_count = lead_change_count + changes,
        last_leader_id = next_leader,
        updated_at = now()
    where challenge_id = challenge_row.id;
  end if;

  return new;
end;
$function$

