-- ATHLTH 1.4.1 advanced group events and challenges.
-- Backward compatible: existing rows keep person organizer / no join requirement.

-- Events --------------------------------------------------------------------
alter table public.community_group_events
  add column if not exists status text not null default 'upcoming',
  add column if not exists organizer_kind text not null default 'person',
  add column if not exists organizer_user_id uuid
    references public.profiles(id) on delete set null,
  add column if not exists capacity integer,
  add column if not exists rsvp_deadline timestamptz,
  add column if not exists meeting_lat double precision,
  add column if not exists meeting_long double precision,
  add column if not exists repeat_rule text,
  add column if not exists repeat_until timestamptz,
  add column if not exists series_id uuid;

update public.community_group_events
set organizer_user_id = creator_id
where organizer_user_id is null
  and organizer_kind = 'person';

alter table public.community_group_events
  drop constraint if exists community_group_events_status_check,
  drop constraint if exists community_group_events_organizer_kind_check,
  drop constraint if exists community_group_events_capacity_check,
  drop constraint if exists community_group_events_repeat_rule_check,
  drop constraint if exists community_group_events_meeting_lat_check,
  drop constraint if exists community_group_events_meeting_long_check;

alter table public.community_group_events
  add constraint community_group_events_status_check
    check (status in ('draft','upcoming','live','completed','cancelled')),
  add constraint community_group_events_organizer_kind_check
    check (organizer_kind in ('person','group')),
  add constraint community_group_events_capacity_check
    check (capacity is null or capacity > 0),
  add constraint community_group_events_repeat_rule_check
    check (repeat_rule is null or repeat_rule in ('weekly')),
  add constraint community_group_events_meeting_lat_check
    check (meeting_lat is null or meeting_lat between -90 and 90),
  add constraint community_group_events_meeting_long_check
    check (meeting_long is null or meeting_long between -180 and 180);

-- Challenges ----------------------------------------------------------------
alter table public.community_group_challenges
  add column if not exists status text not null default 'upcoming',
  add column if not exists organizer_kind text not null default 'person',
  add column if not exists organizer_user_id uuid
    references public.profiles(id) on delete set null,
  add column if not exists scoring_mode text not null default 'cumulative',
  add column if not exists attempt_limit integer,
  add column if not exists route_verification_enabled boolean not null default false,
  add column if not exists route_tolerance_meters integer not null default 100,
  add column if not exists join_required boolean not null default false,
  add column if not exists series_id uuid;

update public.community_group_challenges
set organizer_user_id = creator_id
where organizer_user_id is null
  and organizer_kind = 'person';

alter table public.community_group_challenges
  alter column join_required set default true;

alter table public.community_group_challenges
  drop constraint if exists community_group_challenges_status_check,
  drop constraint if exists community_group_challenges_organizer_kind_check,
  drop constraint if exists community_group_challenges_scoring_mode_check,
  drop constraint if exists community_group_challenges_attempt_limit_check,
  drop constraint if exists community_group_challenges_route_tolerance_check,
  drop constraint if exists community_group_challenges_metric_check;

alter table public.community_group_challenges
  add constraint community_group_challenges_status_check
    check (status in ('draft','upcoming','live','completed','cancelled')),
  add constraint community_group_challenges_organizer_kind_check
    check (organizer_kind in ('person','group')),
  add constraint community_group_challenges_scoring_mode_check
    check (scoring_mode in ('cumulative','best_attempt','complete_target')),
  add constraint community_group_challenges_attempt_limit_check
    check (attempt_limit is null or attempt_limit > 0),
  add constraint community_group_challenges_route_tolerance_check
    check (route_tolerance_meters between 25 and 1000),
  add constraint community_group_challenges_metric_check
    check (metric in ('distance_km','workouts','active_minutes','fastest_time_seconds'));

-- RSVP can include waitlist. Existing direct policies stay for 1.4.0.
alter table public.community_group_event_rsvps
  drop constraint if exists community_group_event_rsvps_status_check;

alter table public.community_group_event_rsvps
  add constraint community_group_event_rsvps_status_check
    check (status in ('going','maybe','not_going','waitlist'));

-- Cohosts -------------------------------------------------------------------
create table if not exists public.community_group_content_hosts (
  group_id uuid not null references public.community_groups(id) on delete cascade,
  content_type text not null check (content_type in ('event','challenge')),
  content_id uuid not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (content_type, content_id, user_id)
);

create index if not exists community_group_content_hosts_group_idx
  on public.community_group_content_hosts(group_id, content_type, content_id);

alter table public.community_group_content_hosts enable row level security;

-- Challenge participants -----------------------------------------------------
create table if not exists public.community_group_challenge_participants (
  group_id uuid not null references public.community_groups(id) on delete cascade,
  challenge_id uuid not null references public.community_group_challenges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  status text not null default 'joined'
    check (status in ('joined','left','completed')),
  primary key (challenge_id, user_id)
);

create index if not exists community_group_challenge_participants_group_idx
  on public.community_group_challenge_participants(group_id, challenge_id, status);

alter table public.community_group_challenge_participants enable row level security;

-- Event / challenge discussions ---------------------------------------------
create table if not exists public.community_group_content_comments (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.community_groups(id) on delete cascade,
  content_type text not null check (content_type in ('event','challenge')),
  content_id uuid not null,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (
    char_length(trim(body)) between 1 and 1200
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists community_group_content_comments_content_idx
  on public.community_group_content_comments(
    group_id,
    content_type,
    content_id,
    created_at
  );

alter table public.community_group_content_comments enable row level security;

-- Helpers -------------------------------------------------------------------
create or replace function private.community_group_content_exists(
  p_group_id uuid,
  p_content_type text,
  p_content_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select case
    when p_content_type = 'event' then exists (
      select 1 from public.community_group_events e
      where e.id = p_content_id and e.group_id = p_group_id
    )
    when p_content_type = 'challenge' then exists (
      select 1 from public.community_group_challenges c
      where c.id = p_content_id and c.group_id = p_group_id
    )
    else false
  end;
$$;

create or replace function private.can_manage_community_group_content(
  p_group_id uuid,
  p_content_type text,
  p_content_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select
    private.can_manage_community_group(p_group_id)
    or case
      when p_content_type = 'event' then exists (
        select 1 from public.community_group_events e
        where e.id = p_content_id
          and e.group_id = p_group_id
          and e.creator_id = p_user_id
      )
      when p_content_type = 'challenge' then exists (
        select 1 from public.community_group_challenges c
        where c.id = p_content_id
          and c.group_id = p_group_id
          and c.creator_id = p_user_id
      )
      else false
    end;
$$;

-- RLS -----------------------------------------------------------------------
drop policy if exists group_content_hosts_select_members
  on public.community_group_content_hosts;
create policy group_content_hosts_select_members
  on public.community_group_content_hosts
  for select to authenticated
  using (private.is_community_group_member(group_id, (select auth.uid())));

drop policy if exists group_content_hosts_insert_managers
  on public.community_group_content_hosts;
create policy group_content_hosts_insert_managers
  on public.community_group_content_hosts
  for insert to authenticated
  with check (
    private.can_manage_community_group_content(
      group_id,
      content_type,
      content_id,
      (select auth.uid())
    )
    and private.is_community_group_member(group_id, user_id)
  );

drop policy if exists group_content_hosts_delete_managers
  on public.community_group_content_hosts;
create policy group_content_hosts_delete_managers
  on public.community_group_content_hosts
  for delete to authenticated
  using (
    private.can_manage_community_group_content(
      group_id,
      content_type,
      content_id,
      (select auth.uid())
    )
  );

drop policy if exists group_challenge_participants_select_members
  on public.community_group_challenge_participants;
create policy group_challenge_participants_select_members
  on public.community_group_challenge_participants
  for select to authenticated
  using (private.is_community_group_member(group_id, (select auth.uid())));

drop policy if exists group_challenge_participants_insert_self
  on public.community_group_challenge_participants;
create policy group_challenge_participants_insert_self
  on public.community_group_challenge_participants
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and private.is_community_group_member(group_id, (select auth.uid()))
  );

drop policy if exists group_challenge_participants_update_self
  on public.community_group_challenge_participants;
create policy group_challenge_participants_update_self
  on public.community_group_challenge_participants
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists group_content_comments_select_members
  on public.community_group_content_comments;
create policy group_content_comments_select_members
  on public.community_group_content_comments
  for select to authenticated
  using (
    private.is_community_group_member(group_id, (select auth.uid()))
    and private.community_group_content_exists(group_id, content_type, content_id)
  );

drop policy if exists group_content_comments_insert_members
  on public.community_group_content_comments;
create policy group_content_comments_insert_members
  on public.community_group_content_comments
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and private.is_community_group_member(group_id, (select auth.uid()))
    and private.community_group_content_exists(group_id, content_type, content_id)
  );

drop policy if exists group_content_comments_delete_author_or_manager
  on public.community_group_content_comments;
create policy group_content_comments_delete_author_or_manager
  on public.community_group_content_comments
  for delete to authenticated
  using (
    author_id = (select auth.uid())
    or private.can_manage_community_group_content(
      group_id,
      content_type,
      content_id,
      (select auth.uid())
    )
  );

grant select, insert, delete
  on public.community_group_content_hosts to authenticated;
grant select, insert, update
  on public.community_group_challenge_participants to authenticated;
grant select, insert, delete
  on public.community_group_content_comments to authenticated;

-- Capacity/waitlist RSVP RPC -------------------------------------------------
create or replace function public.set_community_group_event_rsvp(
  p_event_id uuid,
  p_status text
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  ev public.community_group_events%rowtype;
  resolved_status text := p_status;
  previous_status text;
  going_count integer;
  promote_user uuid;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if p_status not in ('going','maybe','not_going') then
    raise exception 'Invalid RSVP status';
  end if;

  select * into ev
  from public.community_group_events
  where id = p_event_id;

  if not found then
    raise exception 'Event not found';
  end if;

  if not private.is_community_group_member(ev.group_id, actor) then
    raise exception 'Group membership required';
  end if;

  if ev.status = 'cancelled' then
    raise exception 'This event is cancelled';
  end if;

  if ev.rsvp_deadline is not null
     and now() > ev.rsvp_deadline
     and p_status <> 'not_going' then
    raise exception 'RSVP deadline has passed';
  end if;

  select r.status into previous_status
  from public.community_group_event_rsvps r
  where r.event_id = p_event_id
    and r.user_id = actor;

  if p_status = 'going' and ev.capacity is not null then
    select count(*) into going_count
    from public.community_group_event_rsvps r
    where r.event_id = p_event_id
      and r.status = 'going'
      and r.user_id <> actor;

    if going_count >= ev.capacity then
      resolved_status := 'waitlist';
    end if;
  end if;

  insert into public.community_group_event_rsvps(
    group_id,
    event_id,
    user_id,
    status,
    updated_at
  )
  values (
    ev.group_id,
    p_event_id,
    actor,
    resolved_status,
    now()
  )
  on conflict (event_id, user_id)
  do update set
    status = excluded.status,
    updated_at = now();

  if previous_status = 'going'
     and resolved_status <> 'going'
     and ev.capacity is not null then
    select r.user_id into promote_user
    from public.community_group_event_rsvps r
    where r.event_id = p_event_id
      and r.status = 'waitlist'
    order by r.updated_at asc
    limit 1;

    if promote_user is not null then
      update public.community_group_event_rsvps
      set status = 'going', updated_at = now()
      where event_id = p_event_id
        and user_id = promote_user;

      insert into public.social_inbox_events(
        recipient_id,
        kind,
        title,
        message,
        entity_type,
        entity_id,
        group_id
      )
      values (
        promote_user,
        'group_event',
        'You have a spot',
        'A spot opened up for ' || ev.title || '. You are now going.',
        'community_group_event',
        ev.id,
        ev.group_id
      );
    end if;
  end if;

  return resolved_status;
end;
$$;

grant execute on function public.set_community_group_event_rsvp(uuid,text)
  to authenticated;
revoke all on function public.set_community_group_event_rsvp(uuid,text)
  from public, anon;

-- Challenge join / leave -----------------------------------------------------
create or replace function public.set_community_group_challenge_participation(
  p_challenge_id uuid,
  p_join boolean
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  ch public.community_group_challenges%rowtype;
  result_status text;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  select * into ch
  from public.community_group_challenges
  where id = p_challenge_id;

  if not found then
    raise exception 'Challenge not found';
  end if;

  if not private.is_community_group_member(ch.group_id, actor) then
    raise exception 'Group membership required';
  end if;

  if ch.status = 'cancelled' then
    raise exception 'This challenge is cancelled';
  end if;

  result_status := case when p_join then 'joined' else 'left' end;

  insert into public.community_group_challenge_participants(
    group_id,
    challenge_id,
    user_id,
    status,
    joined_at
  )
  values (
    ch.group_id,
    ch.id,
    actor,
    result_status,
    now()
  )
  on conflict (challenge_id, user_id)
  do update set
    status = excluded.status,
    joined_at = case
      when excluded.status = 'joined' then now()
      else public.community_group_challenge_participants.joined_at
    end;

  return result_status;
end;
$$;

grant execute on function public.set_community_group_challenge_participation(uuid,boolean)
  to authenticated;
revoke all on function public.set_community_group_challenge_participation(uuid,boolean)
  from public, anon;

-- Important edit notifications ----------------------------------------------
create or replace function private.notify_group_event_important_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if old.title is distinct from new.title
     or old.starts_at is distinct from new.starts_at
     or old.ends_at is distinct from new.ends_at
     or old.meeting_name is distinct from new.meeting_name
     or old.meeting_lat is distinct from new.meeting_lat
     or old.meeting_long is distinct from new.meeting_long
     or old.activity_config is distinct from new.activity_config
     or old.status is distinct from new.status
  then
    insert into public.social_inbox_events(
      recipient_id,
      kind,
      title,
      message,
      entity_type,
      entity_id,
      group_id
    )
    select
      r.user_id,
      'group_event',
      case
        when new.status = 'cancelled' then 'Event cancelled'
        else 'Event updated'
      end,
      new.title || ' has important changes.',
      'community_group_event',
      new.id,
      new.group_id
    from public.community_group_event_rsvps r
    where r.event_id = new.id
      and r.status in ('going','maybe','waitlist')
      and r.user_id <> (select auth.uid());
  end if;

  return new;
end;
$$;

drop trigger if exists group_event_important_change_notify
  on public.community_group_events;
create trigger group_event_important_change_notify
after update on public.community_group_events
for each row execute function private.notify_group_event_important_change();

create or replace function private.notify_group_challenge_important_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if old.title is distinct from new.title
     or old.starts_at is distinct from new.starts_at
     or old.ends_at is distinct from new.ends_at
     or old.activity_config is distinct from new.activity_config
     or old.scoring_mode is distinct from new.scoring_mode
     or old.attempt_limit is distinct from new.attempt_limit
     or old.route_verification_enabled is distinct from new.route_verification_enabled
     or old.status is distinct from new.status
  then
    insert into public.social_inbox_events(
      recipient_id,
      kind,
      title,
      message,
      entity_type,
      entity_id,
      group_id
    )
    select
      p.user_id,
      'group_challenge',
      case
        when new.status = 'cancelled' then 'Challenge cancelled'
        else 'Challenge updated'
      end,
      new.title || ' has important changes.',
      'community_group_challenge',
      new.id,
      new.group_id
    from public.community_group_challenge_participants p
    where p.challenge_id = new.id
      and p.status in ('joined','completed')
      and p.user_id <> (select auth.uid());
  end if;

  return new;
end;
$$;

drop trigger if exists group_challenge_important_change_notify
  on public.community_group_challenges;
create trigger group_challenge_important_change_notify
after update on public.community_group_challenges
for each row execute function private.notify_group_challenge_important_change();

-- Challenge rule lock after start. Cancellation/status may still change.
create or replace function private.lock_started_group_challenge_rules()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if old.starts_at <= now()
     and (
       old.metric is distinct from new.metric
       or old.target_value is distinct from new.target_value
       or old.activity_config is distinct from new.activity_config
       or old.scoring_mode is distinct from new.scoring_mode
       or old.attempt_limit is distinct from new.attempt_limit
       or old.route_verification_enabled is distinct from new.route_verification_enabled
       or old.route_tolerance_meters is distinct from new.route_tolerance_meters
     )
  then
    raise exception 'Challenge rules are locked after the challenge starts';
  end if;

  return new;
end;
$$;

drop trigger if exists group_challenge_rule_lock
  on public.community_group_challenges;
create trigger group_challenge_rule_lock
before update on public.community_group_challenges
for each row execute function private.lock_started_group_challenge_rules();

revoke all on function private.community_group_content_exists(uuid,text,uuid)
  from public, anon, authenticated;
revoke all on function private.can_manage_community_group_content(uuid,text,uuid,uuid)
  from public, anon, authenticated;
revoke all on function private.notify_group_event_important_change()
  from public, anon, authenticated;
revoke all on function private.notify_group_challenge_important_change()
  from public, anon, authenticated;
revoke all on function private.lock_started_group_challenge_rules()
  from public, anon, authenticated;
