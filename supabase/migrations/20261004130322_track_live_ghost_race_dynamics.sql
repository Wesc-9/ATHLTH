alter table public.live_ghost_race_rooms
  add column sender_max_lead_meters double precision not null default 0,
  add column recipient_max_lead_meters double precision not null default 0,
  add column lead_change_count integer not null default 0
    check (lead_change_count >= 0),
  add column last_leader_id uuid references auth.users(id) on delete set null;

create index if not exists live_ghost_race_rooms_last_leader_idx
  on public.live_ghost_race_rooms (last_leader_id)
  where last_leader_id is not null;

create or replace function private.track_live_ghost_race_gap()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
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

  if sender_location.route_progress_percent is not null
     and recipient_location.route_progress_percent is not null
     and session_row.route_distance_meters is not null
     and session_row.route_distance_meters >= 250 then
    signed_gap :=
      (
        sender_location.route_progress_percent -
        recipient_location.route_progress_percent
      ) / 100.0 * session_row.route_distance_meters;
  else
    signed_gap :=
      sender_location.distance_meters -
      recipient_location.distance_meters;
  end if;

  select * into room_row
  from public.live_ghost_race_rooms
  where challenge_id = challenge_row.id
  for update;

  if not found then
    return new;
  end if;

  sender_best :=
    greatest(room_row.sender_max_lead_meters, signed_gap, 0);
  recipient_best :=
    greatest(room_row.recipient_max_lead_meters, -signed_gap, 0);

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

  if sender_best <> room_row.sender_max_lead_meters
     or recipient_best <> room_row.recipient_max_lead_meters
     or changes > 0
     or (
       next_leader is distinct from room_row.last_leader_id
       and next_leader is not null
     ) then
    update public.live_ghost_race_rooms
    set sender_max_lead_meters = sender_best,
        recipient_max_lead_meters = recipient_best,
        lead_change_count = lead_change_count + changes,
        last_leader_id = next_leader,
        updated_at = now()
    where challenge_id = challenge_row.id;
  end if;

  return new;
end;
$function$;

create trigger live_ghost_race_gap_tracking
after insert or update
on public.live_workout_locations
for each row execute function private.track_live_ghost_race_gap();
