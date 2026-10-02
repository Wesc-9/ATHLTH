create table if not exists public.community_groups (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 2 and 80),
  summary text not null default '' check (char_length(summary) <= 800),
  location_name text not null check (char_length(trim(location_name)) between 2 and 120),
  visibility text not null default 'public'
    check (visibility in ('public','private')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists community_groups_location_idx
  on public.community_groups (lower(location_name), created_at desc);

create table if not exists public.community_group_members (
  group_id uuid not null references public.community_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member'
    check (role in ('owner','admin','member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index if not exists community_group_members_user_idx
  on public.community_group_members (user_id, joined_at desc);

create or replace function private.is_community_group_member(
  p_group_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select exists (
    select 1
    from public.community_group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = p_user_id
  );
$$;

create or replace function public.handle_community_group_owner_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.community_group_members (group_id, user_id, role)
  values (new.id, new.creator_id, 'owner')
  on conflict (group_id, user_id) do update
    set role = 'owner';
  return new;
end;
$$;

revoke all on function public.handle_community_group_owner_membership()
  from public, anon, authenticated;

drop trigger if exists community_group_owner_membership
  on public.community_groups;

create trigger community_group_owner_membership
after insert on public.community_groups
for each row execute function public.handle_community_group_owner_membership();

create table if not exists public.community_group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.community_groups(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists community_group_messages_group_idx
  on public.community_group_messages (group_id, created_at desc);

create table if not exists public.community_group_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.community_groups(id) on delete cascade,
  creator_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 160),
  summary text not null default '' check (char_length(summary) <= 1200),
  activity_type text not null default 'other'
    check (activity_type in ('running','walking','strength','cycling','hike','group_workout','other')),
  starts_at timestamptz not null,
  ends_at timestamptz,
  meeting_name text not null check (char_length(trim(meeting_name)) between 1 and 180),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists community_group_events_group_idx
  on public.community_group_events (group_id, starts_at);

create table if not exists public.community_group_challenges (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.community_groups(id) on delete cascade,
  creator_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 160),
  summary text not null default '' check (char_length(summary) <= 800),
  metric text not null
    check (metric in ('distance_km','workouts','active_minutes')),
  target_value double precision not null check (target_value > 0),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index if not exists community_group_challenges_group_idx
  on public.community_group_challenges (group_id, starts_at, ends_at);

create table if not exists public.community_group_challenge_workouts (
  challenge_id uuid not null references public.community_group_challenges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  workout_id uuid not null,
  contribution double precision not null check (contribution >= 0),
  created_at timestamptz not null default now(),
  primary key (challenge_id, user_id, workout_id)
);

create index if not exists community_group_challenge_workouts_user_idx
  on public.community_group_challenge_workouts (user_id, created_at desc);

alter table public.community_groups enable row level security;
alter table public.community_group_members enable row level security;
alter table public.community_group_messages enable row level security;
alter table public.community_group_events enable row level security;
alter table public.community_group_challenges enable row level security;
alter table public.community_group_challenge_workouts enable row level security;

create policy "groups_select_visible"
  on public.community_groups
  for select to authenticated
  using (
    visibility = 'public'
    or creator_id = (select auth.uid())
    or private.is_community_group_member(id, (select auth.uid()))
  );

create policy "groups_insert_own"
  on public.community_groups
  for insert to authenticated
  with check (creator_id = (select auth.uid()));

create policy "groups_update_creator"
  on public.community_groups
  for update to authenticated
  using (creator_id = (select auth.uid()))
  with check (creator_id = (select auth.uid()));

create policy "groups_delete_creator"
  on public.community_groups
  for delete to authenticated
  using (creator_id = (select auth.uid()));

create policy "group_members_select_members"
  on public.community_group_members
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.is_community_group_member(group_id, (select auth.uid()))
  );

create policy "group_members_join_public"
  on public.community_group_members
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and role = 'member'
    and exists (
      select 1
      from public.community_groups g
      where g.id = group_id
        and g.visibility = 'public'
    )
  );

create policy "group_members_leave_self"
  on public.community_group_members
  for delete to authenticated
  using (
    user_id = (select auth.uid())
    and role <> 'owner'
  );

create policy "group_messages_select_members"
  on public.community_group_messages
  for select to authenticated
  using (
    deleted_at is null
    and private.is_community_group_member(group_id, (select auth.uid()))
  );

create policy "group_messages_insert_members"
  on public.community_group_messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and private.is_community_group_member(group_id, (select auth.uid()))
  );

create policy "group_messages_delete_own"
  on public.community_group_messages
  for delete to authenticated
  using (sender_id = (select auth.uid()));

create policy "group_events_select_members"
  on public.community_group_events
  for select to authenticated
  using (private.is_community_group_member(group_id, (select auth.uid())));

create policy "group_events_insert_members"
  on public.community_group_events
  for insert to authenticated
  with check (
    creator_id = (select auth.uid())
    and private.is_community_group_member(group_id, (select auth.uid()))
  );

create policy "group_events_update_own"
  on public.community_group_events
  for update to authenticated
  using (creator_id = (select auth.uid()))
  with check (
    creator_id = (select auth.uid())
    and private.is_community_group_member(group_id, (select auth.uid()))
  );

create policy "group_events_delete_own"
  on public.community_group_events
  for delete to authenticated
  using (creator_id = (select auth.uid()));

create policy "group_challenges_select_members"
  on public.community_group_challenges
  for select to authenticated
  using (private.is_community_group_member(group_id, (select auth.uid())));

create policy "group_challenges_insert_members"
  on public.community_group_challenges
  for insert to authenticated
  with check (
    creator_id = (select auth.uid())
    and private.is_community_group_member(group_id, (select auth.uid()))
  );

create policy "group_challenges_update_own"
  on public.community_group_challenges
  for update to authenticated
  using (creator_id = (select auth.uid()))
  with check (
    creator_id = (select auth.uid())
    and private.is_community_group_member(group_id, (select auth.uid()))
  );

create policy "group_challenges_delete_own"
  on public.community_group_challenges
  for delete to authenticated
  using (creator_id = (select auth.uid()));

create policy "group_challenge_workouts_select_members"
  on public.community_group_challenge_workouts
  for select to authenticated
  using (
    private.is_community_group_member(
      (select c.group_id
       from public.community_group_challenges c
       where c.id = challenge_id),
      (select auth.uid())
    )
  );

create policy "group_challenge_workouts_insert_self"
  on public.community_group_challenge_workouts
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and private.is_community_group_member(
      (select c.group_id
       from public.community_group_challenges c
       where c.id = challenge_id),
      (select auth.uid())
    )
  );

create policy "group_challenge_workouts_update_self"
  on public.community_group_challenge_workouts
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "group_challenge_workouts_delete_self"
  on public.community_group_challenge_workouts
  for delete to authenticated
  using (user_id = (select auth.uid()));

grant select, insert, update, delete on public.community_groups to authenticated;
grant select, insert, delete on public.community_group_members to authenticated;
grant select, insert, delete on public.community_group_messages to authenticated;
grant select, insert, update, delete on public.community_group_events to authenticated;
grant select, insert, update, delete on public.community_group_challenges to authenticated;
grant select, insert, update, delete on public.community_group_challenge_workouts to authenticated;
