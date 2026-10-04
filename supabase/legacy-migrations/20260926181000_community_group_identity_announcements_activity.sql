-- Community group identity, announcements, member roles and activity.

alter table public.community_groups
  add column if not exists image_url text;

create or replace function private.can_manage_community_group(
  p_group_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select
    exists (
      select 1
      from public.community_groups g
      where g.id = p_group_id
        and g.creator_id = (select auth.uid())
    )
    or exists (
      select 1
      from public.community_group_members gm
      where gm.group_id = p_group_id
        and gm.user_id = (select auth.uid())
        and gm.role in ('owner', 'admin')
    );
$$;

create or replace function private.is_community_group_owner(
  p_group_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select
    exists (
      select 1
      from public.community_groups g
      where g.id = p_group_id
        and g.creator_id = (select auth.uid())
    )
    or exists (
      select 1
      from public.community_group_members gm
      where gm.group_id = p_group_id
        and gm.user_id = (select auth.uid())
        and gm.role = 'owner'
    );
$$;

grant execute on function private.can_manage_community_group(uuid)
  to authenticated;
grant execute on function private.is_community_group_owner(uuid)
  to authenticated;

drop policy if exists groups_update_creator
  on public.community_groups;
drop policy if exists groups_update_managers
  on public.community_groups;
create policy groups_update_managers
  on public.community_groups
  for update
  to authenticated
  using (private.can_manage_community_group(id))
  with check (private.can_manage_community_group(id));

drop policy if exists group_members_update_owner
  on public.community_group_members;
create policy group_members_update_owner
  on public.community_group_members
  for update
  to authenticated
  using (
    role <> 'owner'
    and private.is_community_group_owner(group_id)
  )
  with check (
    role in ('admin', 'member')
    and private.is_community_group_owner(group_id)
  );

grant update on public.community_group_members to authenticated;

create table if not exists public.community_group_announcements (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.community_groups(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 1200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists community_group_announcements_group_idx
  on public.community_group_announcements(group_id, created_at desc);

alter table public.community_group_announcements enable row level security;

drop policy if exists group_announcements_select_members
  on public.community_group_announcements;
create policy group_announcements_select_members
  on public.community_group_announcements
  for select
  to authenticated
  using (
    private.is_community_group_member(group_id, (select auth.uid()))
  );

drop policy if exists group_announcements_insert_managers
  on public.community_group_announcements;
create policy group_announcements_insert_managers
  on public.community_group_announcements
  for insert
  to authenticated
  with check (
    author_id = (select auth.uid())
    and private.can_manage_community_group(group_id)
  );

drop policy if exists group_announcements_update_managers
  on public.community_group_announcements;
create policy group_announcements_update_managers
  on public.community_group_announcements
  for update
  to authenticated
  using (private.can_manage_community_group(group_id))
  with check (private.can_manage_community_group(group_id));

drop policy if exists group_announcements_delete_managers
  on public.community_group_announcements;
create policy group_announcements_delete_managers
  on public.community_group_announcements
  for delete
  to authenticated
  using (private.can_manage_community_group(group_id));

grant select, insert, update, delete
  on public.community_group_announcements
  to authenticated;

create table if not exists public.community_group_activity (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.community_groups(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  kind text not null check (
    kind in (
      'member_joined',
      'announcement',
      'event_created',
      'challenge_created'
    )
  ),
  entity_id uuid,
  headline text not null check (char_length(headline) between 1 and 180),
  detail text,
  created_at timestamptz not null default now()
);

create index if not exists community_group_activity_group_idx
  on public.community_group_activity(group_id, created_at desc);

alter table public.community_group_activity enable row level security;

drop policy if exists group_activity_select_members
  on public.community_group_activity;
create policy group_activity_select_members
  on public.community_group_activity
  for select
  to authenticated
  using (
    private.is_community_group_member(group_id, (select auth.uid()))
  );

grant select on public.community_group_activity to authenticated;

create or replace function public.log_community_group_activity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_group_id uuid;
  v_actor_id uuid;
  v_kind text;
  v_entity_id uuid;
  v_headline text;
  v_detail text;
begin
  if tg_table_name = 'community_group_members' then
    if new.role = 'owner' then
      return new;
    end if;
    v_group_id := new.group_id;
    v_actor_id := new.user_id;
    v_kind := 'member_joined';
    v_entity_id := null;
    v_headline := 'New member joined';
    v_detail := null;
  elsif tg_table_name = 'community_group_announcements' then
    v_group_id := new.group_id;
    v_actor_id := new.author_id;
    v_kind := 'announcement';
    v_entity_id := new.id;
    v_headline := 'New group update';
    v_detail := left(new.body, 300);
  elsif tg_table_name = 'community_group_events' then
    v_group_id := new.group_id;
    v_actor_id := new.creator_id;
    v_kind := 'event_created';
    v_entity_id := new.id;
    v_headline := 'New event: ' || new.title;
    v_detail := new.meeting_name;
  elsif tg_table_name = 'community_group_challenges' then
    v_group_id := new.group_id;
    v_actor_id := new.creator_id;
    v_kind := 'challenge_created';
    v_entity_id := new.id;
    v_headline := 'New challenge: ' || new.title;
    v_detail := null;
  else
    return new;
  end if;

  insert into public.community_group_activity(
    group_id,
    actor_id,
    kind,
    entity_id,
    headline,
    detail
  )
  values (
    v_group_id,
    v_actor_id,
    v_kind,
    v_entity_id,
    v_headline,
    v_detail
  );

  return new;
end;
$$;

revoke all on function public.log_community_group_activity()
  from public, anon, authenticated;

drop trigger if exists community_group_member_activity
  on public.community_group_members;
create trigger community_group_member_activity
after insert on public.community_group_members
for each row execute function public.log_community_group_activity();

drop trigger if exists community_group_announcement_activity
  on public.community_group_announcements;
create trigger community_group_announcement_activity
after insert on public.community_group_announcements
for each row execute function public.log_community_group_activity();

drop trigger if exists community_group_event_activity
  on public.community_group_events;
create trigger community_group_event_activity
after insert on public.community_group_events
for each row execute function public.log_community_group_activity();

drop trigger if exists community_group_challenge_activity
  on public.community_group_challenges;
create trigger community_group_challenge_activity
after insert on public.community_group_challenges
for each row execute function public.log_community_group_activity();

create or replace function private.can_view_profile_card(owner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select
    (select auth.uid()) = owner_id
    or exists (
      select 1
      from public.user_blocks b
      where b.blocker_id = (select auth.uid())
        and b.blocked_id = owner_id
    )
    or (
      not private.is_blocked(owner_id)
      and (
        coalesce((
          select s.discoverable
          from public.profile_social_settings s
          where s.user_id = owner_id
        ), false)
        or private.are_friends(owner_id)
        or exists (
          select 1
          from public.friend_requests fr
          where (
            (fr.sender_id = (select auth.uid()) and fr.recipient_id = owner_id)
            or (fr.recipient_id = (select auth.uid()) and fr.sender_id = owner_id)
          )
          and fr.status = 'pending'
        )
        or exists (
          select 1
          from public.direct_conversations dc
          where dc.request_status in ('pending', 'accepted')
            and (
              (dc.user_a = (select auth.uid()) and dc.user_b = owner_id)
              or (dc.user_b = (select auth.uid()) and dc.user_a = owner_id)
            )
        )
        or exists (
          select 1
          from public.social_challenge_participants me
          join public.social_challenge_participants them
            on them.challenge_id = me.challenge_id
          where me.user_id = (select auth.uid())
            and them.user_id = owner_id
            and me.state in ('creator','invited','accepted')
            and them.state in ('creator','invited','accepted')
        )
        or exists (
          select 1
          from public.community_group_members me
          join public.community_group_members them
            on them.group_id = me.group_id
          where me.user_id = (select auth.uid())
            and them.user_id = owner_id
        )
      )
    );
$$;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'community-group-images',
  'community-group-images',
  true,
  5242880,
  array['image/jpeg','image/png','image/heic','image/heif']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists community_group_images_insert_managers
  on storage.objects;
create policy community_group_images_insert_managers
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'community-group-images'
    and private.can_manage_community_group(
      ((storage.foldername(name))[1])::uuid
    )
  );

drop policy if exists community_group_images_update_managers
  on storage.objects;
create policy community_group_images_update_managers
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'community-group-images'
    and private.can_manage_community_group(
      ((storage.foldername(name))[1])::uuid
    )
  )
  with check (
    bucket_id = 'community-group-images'
    and private.can_manage_community_group(
      ((storage.foldername(name))[1])::uuid
    )
  );

drop policy if exists community_group_images_delete_managers
  on storage.objects;
create policy community_group_images_delete_managers
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'community-group-images'
    and private.can_manage_community_group(
      ((storage.foldername(name))[1])::uuid
    )
  );
