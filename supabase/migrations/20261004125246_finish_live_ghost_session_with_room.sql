create or replace function private.sync_live_ghost_race_room()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  cid uuid := coalesce(new.challenge_id, old.challenge_id);
  c public.ghost_race_challenges%rowtype;
  sender_row public.live_ghost_race_participants%rowtype;
  recipient_row public.live_ghost_race_participants%rowtype;
  room public.live_ghost_race_rooms%rowtype;
  resolved_winner uuid;
  resolved_finished_at timestamptz;
begin
  select * into c
  from public.ghost_race_challenges
  where id = cid;

  if not found or c.status <> 'accepted' then
    return coalesce(new, old);
  end if;

  insert into public.live_ghost_race_rooms(challenge_id)
  values (cid)
  on conflict (challenge_id) do nothing;

  select * into sender_row
  from public.live_ghost_race_participants
  where challenge_id = cid
    and user_id = c.sender_id;

  select * into recipient_row
  from public.live_ghost_race_participants
  where challenge_id = cid
    and user_id = c.recipient_id;

  select * into room
  from public.live_ghost_race_rooms
  where challenge_id = cid
  for update;

  if sender_row.ready is true and recipient_row.ready is true then
    if room.status = 'lobby' then
      update public.live_ghost_race_rooms
      set status = 'countdown',
          countdown_started_at = now(),
          starts_at = now() + interval '5 seconds',
          updated_at = now()
      where challenge_id = cid;
    elsif room.status = 'countdown'
      and room.starts_at is not null
      and room.starts_at <= now() then
      update public.live_ghost_race_rooms
      set status = 'racing',
          updated_at = now()
      where challenge_id = cid;
    end if;
  elsif room.status = 'countdown'
    and (room.starts_at is null or room.starts_at > now()) then
    update public.live_ghost_race_rooms
    set status = 'lobby',
        countdown_started_at = null,
        starts_at = null,
        updated_at = now()
    where challenge_id = cid;
  end if;

  if sender_row.finished_at is not null
     and recipient_row.finished_at is not null
     and sender_row.elapsed_seconds is not null
     and recipient_row.elapsed_seconds is not null then
    if abs(sender_row.elapsed_seconds - recipient_row.elapsed_seconds) < 0.5 then
      resolved_winner := null;
    elsif sender_row.elapsed_seconds < recipient_row.elapsed_seconds then
      resolved_winner := c.sender_id;
    else
      resolved_winner := c.recipient_id;
    end if;

    resolved_finished_at :=
      greatest(sender_row.finished_at, recipient_row.finished_at);

    update public.live_ghost_race_rooms
    set status = 'finished',
        winner_id = resolved_winner,
        finished_at = resolved_finished_at,
        updated_at = now()
    where challenge_id = cid;

    update public.live_workout_sessions
    set status = 'completed',
        ended_at = coalesce(ended_at, resolved_finished_at),
        updated_at = now()
    where ghost_challenge_id = cid
      and status in ('active','paused');
  end if;

  return coalesce(new, old);
end;
$function$;
