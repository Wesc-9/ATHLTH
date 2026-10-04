create table public.live_ghost_race_rooms (
  challenge_id uuid primary key references public.ghost_race_challenges(id) on delete cascade,
  status text not null default 'lobby'
    check (status in ('lobby','countdown','racing','finished','cancelled')),
  countdown_started_at timestamptz,
  starts_at timestamptz,
  finished_at timestamptz,
  winner_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.live_ghost_race_participants (
  challenge_id uuid not null references public.ghost_race_challenges(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  ready boolean not null default false,
  device_type text check (device_type is null or device_type in ('iphone','apple_watch')),
  joined_at timestamptz not null default now(),
  ready_at timestamptz,
  finished_at timestamptz,
  elapsed_seconds double precision check (elapsed_seconds is null or elapsed_seconds >= 0),
  updated_at timestamptz not null default now(),
  primary key (challenge_id, user_id)
);

alter table public.live_ghost_race_rooms enable row level security;
alter table public.live_ghost_race_participants enable row level security;

revoke all on table public.live_ghost_race_rooms from anon;
revoke all on table public.live_ghost_race_participants from anon;
revoke all on table public.live_ghost_race_rooms from authenticated;
revoke all on table public.live_ghost_race_participants from authenticated;

grant select on table public.live_ghost_race_rooms to authenticated;
grant select, insert, update, delete on table public.live_ghost_race_participants to authenticated;

create policy "live ghost rooms visible to participants"
on public.live_ghost_race_rooms
for select to authenticated
using (
  exists (
    select 1
    from public.ghost_race_challenges c
    where c.id = challenge_id
      and (select auth.uid()) in (c.sender_id, c.recipient_id)
  )
);

create policy "live ghost participants visible to race participants"
on public.live_ghost_race_participants
for select to authenticated
using (
  exists (
    select 1
    from public.ghost_race_challenges c
    where c.id = challenge_id
      and (select auth.uid()) in (c.sender_id, c.recipient_id)
  )
);

create policy "live ghost participants can join themselves"
on public.live_ghost_race_participants
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.ghost_race_challenges c
    where c.id = challenge_id
      and c.status = 'accepted'
      and c.expires_at > now()
      and (select auth.uid()) in (c.sender_id, c.recipient_id)
  )
);

create policy "live ghost participants can update themselves"
on public.live_ghost_race_participants
for update to authenticated
using (user_id = (select auth.uid()))
with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.ghost_race_challenges c
    where c.id = challenge_id
      and c.status = 'accepted'
      and (select auth.uid()) in (c.sender_id, c.recipient_id)
  )
);

create policy "live ghost participants can leave themselves"
on public.live_ghost_race_participants
for delete to authenticated
using (user_id = (select auth.uid()));

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

    update public.live_ghost_race_rooms
    set status = 'finished',
        winner_id = resolved_winner,
        finished_at = greatest(sender_row.finished_at, recipient_row.finished_at),
        updated_at = now()
    where challenge_id = cid;
  end if;

  return coalesce(new, old);
end;
$function$;

create trigger live_ghost_race_participant_sync
after insert or update or delete
on public.live_ghost_race_participants
for each row execute function private.sync_live_ghost_race_room();

drop policy if exists "live_workout_locations_insert_participant"
on public.live_workout_locations;

create policy "live_workout_locations_insert_participant"
on public.live_workout_locations
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.live_workout_sessions l
    where l.id = live_workout_locations.session_id
      and l.status in ('active','paused')
      and (l.owner_id = (select auth.uid()) or l.opponent_user_id = (select auth.uid()))
      and (
        coalesce((
          select settings.share_live_workout_location
          from public.profile_social_settings settings
          where settings.user_id = (select auth.uid())
        ), false)
        or (
          l.ghost_challenge_id is not null
          and exists (
            select 1
            from public.live_ghost_race_participants p
            where p.challenge_id = l.ghost_challenge_id
              and p.user_id = (select auth.uid())
              and p.ready = true
          )
        )
      )
  )
  and (
    heart_rate_bpm is null
    or coalesce((
      select settings.share_live_workout_heart_rate
      from public.profile_social_settings settings
      where settings.user_id = (select auth.uid())
    ), false)
  )
);

drop policy if exists "live_workout_locations_update_participant"
on public.live_workout_locations;

create policy "live_workout_locations_update_participant"
on public.live_workout_locations
for update to authenticated
using (user_id = (select auth.uid()))
with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.live_workout_sessions l
    where l.id = live_workout_locations.session_id
      and l.status in ('active','paused')
      and (l.owner_id = (select auth.uid()) or l.opponent_user_id = (select auth.uid()))
      and (
        coalesce((
          select settings.share_live_workout_location
          from public.profile_social_settings settings
          where settings.user_id = (select auth.uid())
        ), false)
        or (
          l.ghost_challenge_id is not null
          and exists (
            select 1
            from public.live_ghost_race_participants p
            where p.challenge_id = l.ghost_challenge_id
              and p.user_id = (select auth.uid())
              and p.ready = true
          )
        )
      )
  )
  and (
    heart_rate_bpm is null
    or coalesce((
      select settings.share_live_workout_heart_rate
      from public.profile_social_settings settings
      where settings.user_id = (select auth.uid())
    ), false)
  )
);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='live_ghost_race_rooms'
  ) then
    alter publication supabase_realtime add table public.live_ghost_race_rooms;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='live_ghost_race_participants'
  ) then
    alter publication supabase_realtime add table public.live_ghost_race_participants;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='live_workout_locations'
  ) then
    alter publication supabase_realtime add table public.live_workout_locations;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='live_workout_sessions'
  ) then
    alter publication supabase_realtime add table public.live_workout_sessions;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='ghost_race_challenges'
  ) then
    alter publication supabase_realtime add table public.ghost_race_challenges;
  end if;
end
$$;
