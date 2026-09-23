create table if not exists public.community_events (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  summary text not null default '' check (char_length(summary) <= 1200),
  activity_type text not null check (activity_type in ('running','walking','strength','cycling','hike','group_workout','other')),
  visibility text not null default 'public' check (visibility in ('public','friends','private')),
  status text not null default 'upcoming' check (status in ('upcoming','cancelled','completed')),
  starts_at timestamptz not null,
  ends_at timestamptz,
  meeting_name text not null check (char_length(meeting_name) between 1 and 180),
  meeting_details text check (meeting_details is null or char_length(meeting_details) <= 500),
  latitude double precision check (latitude is null or latitude between -90 and 90),
  longitude double precision check (longitude is null or longitude between -180 and 180),
  max_participants integer check (max_participants is null or max_participants between 2 and 500),
  pace_label text check (pace_label is null or char_length(pace_label) <= 80),
  route_id uuid,
  route_title text check (route_title is null or char_length(route_title) <= 180),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at),
  check ((latitude is null and longitude is null) or (latitude is not null and longitude is not null))
);

create table if not exists public.community_event_participants (
  event_id uuid not null references public.community_events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create index if not exists community_events_status_starts_at_idx
  on public.community_events (status, starts_at);
create index if not exists community_events_creator_id_idx
  on public.community_events (creator_id);
create index if not exists community_events_visibility_starts_at_idx
  on public.community_events (visibility, starts_at);
create index if not exists community_event_participants_user_id_idx
  on public.community_event_participants (user_id);

alter table public.community_events enable row level security;
alter table public.community_event_participants enable row level security;

revoke all on table public.community_events from anon;
revoke all on table public.community_event_participants from anon;
grant select, insert, update, delete on table public.community_events to authenticated;
grant select, insert, delete on table public.community_event_participants to authenticated;

drop policy if exists "community_events_select_visible" on public.community_events;
create policy "community_events_select_visible"
on public.community_events
for select
to authenticated
using (
  creator_id = (select auth.uid())
  or visibility = 'public'
  or (
    visibility = 'friends'
    and exists (
      select 1
      from public.friendships f
      where
        (f.user_a = community_events.creator_id and f.user_b = (select auth.uid()))
        or
        (f.user_b = community_events.creator_id and f.user_a = (select auth.uid()))
    )
  )
);

drop policy if exists "community_events_insert_own" on public.community_events;
create policy "community_events_insert_own"
on public.community_events
for insert
to authenticated
with check (creator_id = (select auth.uid()));

drop policy if exists "community_events_update_own" on public.community_events;
create policy "community_events_update_own"
on public.community_events
for update
to authenticated
using (creator_id = (select auth.uid()))
with check (creator_id = (select auth.uid()));

drop policy if exists "community_events_delete_own" on public.community_events;
create policy "community_events_delete_own"
on public.community_events
for delete
to authenticated
using (creator_id = (select auth.uid()));

drop policy if exists "community_event_participants_select_visible" on public.community_event_participants;
create policy "community_event_participants_select_visible"
on public.community_event_participants
for select
to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1
    from public.community_events e
    where e.id = community_event_participants.event_id
  )
);

drop policy if exists "community_event_participants_join_visible" on public.community_event_participants;
create policy "community_event_participants_join_visible"
on public.community_event_participants
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.community_events e
    where e.id = community_event_participants.event_id
      and e.creator_id <> (select auth.uid())
      and e.status = 'upcoming'
      and e.starts_at > now()
  )
);

drop policy if exists "community_event_participants_leave_own" on public.community_event_participants;
create policy "community_event_participants_leave_own"
on public.community_event_participants
for delete
to authenticated
using (user_id = (select auth.uid()));
