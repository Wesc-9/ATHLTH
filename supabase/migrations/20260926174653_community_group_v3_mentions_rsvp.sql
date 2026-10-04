-- ATHLTH group v3: owner/admin/contributor/member permissions,
-- join approvals & invites, per-group notifications, pinned updates,
-- event RSVP, member content controls and @mention notifications.

alter table public.community_groups
  add column if not exists join_mode text not null default 'open',
  add column if not exists members_can_create_content boolean not null default true;

alter table public.community_groups
  drop constraint if exists community_groups_join_mode_check;

alter table public.community_groups
  add constraint community_groups_join_mode_check
  check (join_mode in ('open', 'approval', 'invite_only'));

-- Existing private groups should not silently become open-join.
update public.community_groups
set join_mode = 'invite_only'
where visibility = 'private'
  and join_mode = 'open';

alter table public.community_group_announcements
  add column if not exists pinned_at timestamptz;

create unique index if not exists community_group_one_pinned_update_idx
  on public.community_group_announcements(group_id)
  where pinned_at is not null;

alter table public.user_preferences
  add column if not exists mention_notifications_enabled boolean not null default true;

alter table public.social_inbox_events
  add column if not exists group_id uuid
    references public.community_groups(id) on delete cascade;

create index if not exists social_inbox_events_group_idx
  on public.social_inbox_events(group_id, created_at desc);

alter table public.social_inbox_events
  drop constraint if exists social_inbox_events_kind_check;

alter table public.social_inbox_events
  add constraint social_inbox_events_kind_check
  check (
    kind in (
      'friend_request',
      'friend_accepted',
      'challenge_invite',
      'challenge_result',
      'reaction',
      'workout_invite',
      'workout_invite_accepted',
      'message',
      'message_request',
      'message_request_accepted',
      'mention',
      'group_message',
      'group_update',
      'group_event',
      'group_challenge',
      'group_invite',
      'group_join_request',
      'group_join_approved'
    )
  );

create table if not exists public.community_group_join_requests (
  group_id uuid not null references public.community_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  responded_by uuid references public.profiles(id) on delete set null,
  primary key (group_id, user_id)
);

create index if not exists community_group_join_requests_status_idx
  on public.community_group_join_requests(group_id, status, created_at desc);

create table if not exists public.community_group_invites (
  group_id uuid not null references public.community_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  invited_by uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  primary key (group_id, user_id)
);

create index if not exists community_group_invites_user_idx
  on public.community_group_invites(user_id, status, created_at desc);

create table if not exists public.community_group_notification_preferences (
  group_id uuid not null references public.community_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  mode text not null default 'important'
    check (mode in ('all', 'important', 'muted')),
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.community_group_event_rsvps (
  group_id uuid not null references public.community_groups(id) on delete cascade,
  event_id uuid not null references public.community_group_events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null
    check (status in ('going', 'maybe', 'not_going')),
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create index if not exists community_group_event_rsvps_group_idx
  on public.community_group_event_rsvps(group_id, event_id, status);

alter table public.community_group_join_requests enable row level security;
alter table public.community_group_invites enable row level security;
alter table public.community_group_notification_preferences enable row level security;
alter table public.community_group_event_rsvps enable row level security;

create or replace function private.community_group_role(
  p_group_id uuid,
  p_user_id uuid
)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select gm.role
  from public.community_group_members gm
  where gm.group_id = p_group_id
    and gm.user_id = p_user_id
  limit 1;
$$;

create or replace function private.can_create_community_group_content(
  p_group_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
    select 1
    from public.community_groups g
    left join public.community_group_members gm
      on gm.group_id = g.id
     and gm.user_id = p_user_id
    where g.id = p_group_id
      and (
        g.creator_id = p_user_id
        or gm.role in ('owner', 'admin')
        or (
          gm.role = 'member'
          and g.members_can_create_content = true
        )
      )
  );
$$;

create or replace function private.community_group_notification_mode(
  p_group_id uuid,
  p_user_id uuid
)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select coalesce(
    (
      select p.mode
      from public.community_group_notification_preferences p
      where p.group_id = p_group_id
        and p.user_id = p_user_id
    ),
    'important'
  );
$$;

create or replace function private.mention_notifications_enabled(
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select coalesce(
    (
      select up.mention_notifications_enabled
      from public.user_preferences up
      where up.user_id = p_user_id
    ),
    true
  );
$$;

-- Only the group owner can delete the group. Admin retains every other
-- management permission through can_manage_community_group().
drop policy if exists groups_delete_creator
  on public.community_groups;
drop policy if exists groups_delete_managers
  on public.community_groups;
drop policy if exists groups_delete_owner
  on public.community_groups;

create policy groups_delete_owner
  on public.community_groups
  for delete
  to authenticated
  using (creator_id = (select auth.uid()));

-- Open joining is allowed only for public groups explicitly configured as open.
drop policy if exists group_members_join_public
  on public.community_group_members;

create policy group_members_join_public
  on public.community_group_members
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and role = 'member'
    and exists (
      select 1
      from public.community_groups g
      where g.id = group_id
        and g.visibility = 'public'
        and g.join_mode = 'open'
    )
  );

-- Managers can assign Admin / Contributor / Member, but never alter owner.
drop policy if exists group_members_update_owner
  on public.community_group_members;
drop policy if exists group_members_update_managers
  on public.community_group_members;

create policy group_members_update_managers
  on public.community_group_members
  for update
  to authenticated
  using (
    role <> 'owner'
    and private.can_manage_community_group(group_id)
  )
  with check (
    role in ('admin', 'contributor', 'member')
    and private.can_manage_community_group(group_id)
  );

-- Public groups remain discoverable. Invited users and users with an existing
-- request can also resolve a private group so invitations/deep links work.
drop policy if exists groups_select_visible
  on public.community_groups;

create policy groups_select_visible
  on public.community_groups
  for select
  to authenticated
  using (
    visibility = 'public'
    or creator_id = (select auth.uid())
    or private.is_community_group_member(id, (select auth.uid()))
    or exists (
      select 1
      from public.community_group_invites i
      where i.group_id = id
        and i.user_id = (select auth.uid())
        and i.status = 'pending'
    )
    or exists (
      select 1
      from public.community_group_join_requests r
      where r.group_id = id
        and r.user_id = (select auth.uid())
        and r.status = 'pending'
    )
  );

-- Join request RLS.
drop policy if exists group_join_requests_select
  on public.community_group_join_requests;
create policy group_join_requests_select
  on public.community_group_join_requests
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or private.can_manage_community_group(group_id)
  );

drop policy if exists group_join_requests_insert_self
  on public.community_group_join_requests;
create policy group_join_requests_insert_self
  on public.community_group_join_requests
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.community_groups g
      where g.id = group_id
        and g.join_mode = 'approval'
    )
  );

drop policy if exists group_join_requests_delete
  on public.community_group_join_requests;
create policy group_join_requests_delete
  on public.community_group_join_requests
  for delete
  to authenticated
  using (
    (user_id = (select auth.uid()) and status = 'pending')
    or private.can_manage_community_group(group_id)
  );

-- Invite RLS.
drop policy if exists group_invites_select
  on public.community_group_invites;
create policy group_invites_select
  on public.community_group_invites
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or private.can_manage_community_group(group_id)
  );

drop policy if exists group_invites_insert_managers
  on public.community_group_invites;
create policy group_invites_insert_managers
  on public.community_group_invites
  for insert
  to authenticated
  with check (
    invited_by = (select auth.uid())
    and private.can_manage_community_group(group_id)
  );

-- Per-member group notification preference.
drop policy if exists group_notification_preferences_select_self
  on public.community_group_notification_preferences;
create policy group_notification_preferences_select_self
  on public.community_group_notification_preferences
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists group_notification_preferences_insert_self
  on public.community_group_notification_preferences;
create policy group_notification_preferences_insert_self
  on public.community_group_notification_preferences
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and private.is_community_group_member(group_id, (select auth.uid()))
  );

drop policy if exists group_notification_preferences_update_self
  on public.community_group_notification_preferences;
create policy group_notification_preferences_update_self
  on public.community_group_notification_preferences
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Event RSVP is visible to group members; only the user can change their RSVP.
drop policy if exists group_event_rsvps_select_members
  on public.community_group_event_rsvps;
create policy group_event_rsvps_select_members
  on public.community_group_event_rsvps
  for select
  to authenticated
  using (
    private.is_community_group_member(group_id, (select auth.uid()))
  );

drop policy if exists group_event_rsvps_insert_self
  on public.community_group_event_rsvps;
create policy group_event_rsvps_insert_self
  on public.community_group_event_rsvps
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and private.is_community_group_member(group_id, (select auth.uid()))
    and exists (
      select 1
      from public.community_group_events e
      where e.id = event_id
        and e.group_id = group_id
    )
  );

drop policy if exists group_event_rsvps_update_self
  on public.community_group_event_rsvps;
create policy group_event_rsvps_update_self
  on public.community_group_event_rsvps
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists group_event_rsvps_delete_self
  on public.community_group_event_rsvps;
create policy group_event_rsvps_delete_self
  on public.community_group_event_rsvps
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

grant select, insert, delete
  on public.community_group_join_requests
  to authenticated;
grant select, insert
  on public.community_group_invites
  to authenticated;
grant select, insert, update
  on public.community_group_notification_preferences
  to authenticated;
grant select, insert, update, delete
  on public.community_group_event_rsvps
  to authenticated;

-- Event/challenge creation is governed by the group's content setting.
-- Contributor is intentionally excluded: that role is update-only.
drop policy if exists group_events_insert_members
  on public.community_group_events;
drop policy if exists group_events_update_own
  on public.community_group_events;
drop policy if exists group_events_delete_own
  on public.community_group_events;

create policy group_events_insert_allowed
  on public.community_group_events
  for insert
  to authenticated
  with check (
    creator_id = (select auth.uid())
    and private.can_create_community_group_content(
      group_id,
      (select auth.uid())
    )
  );

create policy group_events_update_allowed
  on public.community_group_events
  for update
  to authenticated
  using (
    private.can_manage_community_group(group_id)
    or (
      creator_id = (select auth.uid())
      and private.can_create_community_group_content(
        group_id,
        (select auth.uid())
      )
    )
  )
  with check (
    private.can_manage_community_group(group_id)
    or (
      creator_id = (select auth.uid())
      and private.can_create_community_group_content(
        group_id,
        (select auth.uid())
      )
    )
  );

create policy group_events_delete_allowed
  on public.community_group_events
  for delete
  to authenticated
  using (
    private.can_manage_community_group(group_id)
    or (
      creator_id = (select auth.uid())
      and private.can_create_community_group_content(
        group_id,
        (select auth.uid())
      )
    )
  );

drop policy if exists group_challenges_insert_members
  on public.community_group_challenges;
drop policy if exists group_challenges_update_own
  on public.community_group_challenges;
drop policy if exists group_challenges_delete_own
  on public.community_group_challenges;

create policy group_challenges_insert_allowed
  on public.community_group_challenges
  for insert
  to authenticated
  with check (
    creator_id = (select auth.uid())
    and private.can_create_community_group_content(
      group_id,
      (select auth.uid())
    )
  );

create policy group_challenges_update_allowed
  on public.community_group_challenges
  for update
  to authenticated
  using (
    private.can_manage_community_group(group_id)
    or (
      creator_id = (select auth.uid())
      and private.can_create_community_group_content(
        group_id,
        (select auth.uid())
      )
    )
  )
  with check (
    private.can_manage_community_group(group_id)
    or (
      creator_id = (select auth.uid())
      and private.can_create_community_group_content(
        group_id,
        (select auth.uid())
      )
    )
  );

create policy group_challenges_delete_allowed
  on public.community_group_challenges
  for delete
  to authenticated
  using (
    private.can_manage_community_group(group_id)
    or (
      creator_id = (select auth.uid())
      and private.can_create_community_group_content(
        group_id,
        (select auth.uid())
      )
    )
  );

-- Joining / approval / invitation RPCs keep membership changes atomic.
create or replace function public.request_community_group_join(
  p_group_id uuid
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  v_visibility text;
  v_join_mode text;
  manager record;
  group_name text;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if private.is_community_group_member(p_group_id, actor) then
    return 'joined';
  end if;

  select g.visibility, g.join_mode, g.name
    into v_visibility, v_join_mode, group_name
  from public.community_groups g
  where g.id = p_group_id;

  if not found then
    raise exception 'Group not found';
  end if;

  if exists (
    select 1
    from public.community_group_invites i
    where i.group_id = p_group_id
      and i.user_id = actor
      and i.status = 'pending'
  ) then
    return 'invited';
  end if;

  if v_join_mode = 'open' and v_visibility = 'public' then
    insert into public.community_group_members(group_id, user_id, role)
    values (p_group_id, actor, 'member')
    on conflict (group_id, user_id) do nothing;

    return 'joined';
  end if;

  if v_join_mode <> 'approval' then
    return 'invite_only';
  end if;

  insert into public.community_group_join_requests(
    group_id,
    user_id,
    status,
    created_at,
    responded_at,
    responded_by
  )
  values (
    p_group_id,
    actor,
    'pending',
    now(),
    null,
    null
  )
  on conflict (group_id, user_id)
  do update set
    status = 'pending',
    created_at = now(),
    responded_at = null,
    responded_by = null;

  for manager in
    select gm.user_id
    from public.community_group_members gm
    where gm.group_id = p_group_id
      and gm.role in ('owner', 'admin')
  loop
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
      manager.user_id,
      'group_join_request',
      'New group join request',
      coalesce(group_name, 'Group') || ' has a new membership request.',
      'community_group',
      p_group_id,
      p_group_id
    );
  end loop;

  return 'requested';
end;
$$;

create or replace function public.respond_community_group_join_request(
  p_group_id uuid,
  p_user_id uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  group_name text;
begin
  if actor is null
     or not private.can_manage_community_group(p_group_id) then
    raise exception 'Group management permission required';
  end if;

  if not exists (
    select 1
    from public.community_group_join_requests r
    where r.group_id = p_group_id
      and r.user_id = p_user_id
      and r.status = 'pending'
  ) then
    raise exception 'Pending request not found';
  end if;

  update public.community_group_join_requests
  set
    status = case when p_accept then 'approved' else 'declined' end,
    responded_at = now(),
    responded_by = actor
  where group_id = p_group_id
    and user_id = p_user_id;

  if p_accept then
    insert into public.community_group_members(group_id, user_id, role)
    values (p_group_id, p_user_id, 'member')
    on conflict (group_id, user_id) do update
      set role = case
        when public.community_group_members.role = 'owner'
          then 'owner'
        else public.community_group_members.role
      end;

    select g.name into group_name
    from public.community_groups g
    where g.id = p_group_id;

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
      p_user_id,
      'group_join_approved',
      'You joined ' || coalesce(group_name, 'the group'),
      'Your membership request was approved.',
      'community_group',
      p_group_id,
      p_group_id
    );
  end if;
end;
$$;

create or replace function public.invite_community_group_member(
  p_group_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  group_name text;
begin
  if actor is null
     or not private.can_manage_community_group(p_group_id) then
    raise exception 'Group management permission required';
  end if;

  if p_user_id = actor
     or private.is_community_group_member(p_group_id, p_user_id) then
    raise exception 'User is already a group member';
  end if;

  insert into public.community_group_invites(
    group_id,
    user_id,
    invited_by,
    status,
    created_at,
    responded_at
  )
  values (
    p_group_id,
    p_user_id,
    actor,
    'pending',
    now(),
    null
  )
  on conflict (group_id, user_id)
  do update set
    invited_by = excluded.invited_by,
    status = 'pending',
    created_at = now(),
    responded_at = null;

  select g.name into group_name
  from public.community_groups g
  where g.id = p_group_id;

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
    p_user_id,
    'group_invite',
    'Group invitation',
    'You were invited to ' || coalesce(group_name, 'a group') || '.',
    'community_group',
    p_group_id,
    p_group_id
  );
end;
$$;

create or replace function public.respond_community_group_invite(
  p_group_id uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.community_group_invites i
    where i.group_id = p_group_id
      and i.user_id = actor
      and i.status = 'pending'
  ) then
    raise exception 'Pending invitation not found';
  end if;

  update public.community_group_invites
  set
    status = case when p_accept then 'accepted' else 'declined' end,
    responded_at = now()
  where group_id = p_group_id
    and user_id = actor;

  if p_accept then
    insert into public.community_group_members(group_id, user_id, role)
    values (p_group_id, actor, 'member')
    on conflict (group_id, user_id) do nothing;
  end if;
end;
$$;

grant execute on function public.request_community_group_join(uuid)
  to authenticated;
grant execute on function public.respond_community_group_join_request(uuid, uuid, boolean)
  to authenticated;
grant execute on function public.invite_community_group_member(uuid, uuid)
  to authenticated;
grant execute on function public.respond_community_group_invite(uuid, boolean)
  to authenticated;

-- Direct-message @mention: replace the ordinary message inbox event with a
-- mention event when the recipient is explicitly tagged and mention alerts
-- are enabled. This avoids duplicate message + mention alerts.
create or replace function private.after_direct_message_insert()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  sender_name text;
  recipient_username text;
  preview text;
  is_mention boolean := false;
begin
  update public.direct_conversations
  set
    last_message_at = new.created_at,
    updated_at = now()
  where id = new.conversation_id;

  select
    coalesce(nullif(p.username::text, ''), nullif(p.display_name, ''), 'A friend')
  into sender_name
  from public.profiles p
  where p.id = new.sender_id;

  select p.username::text
    into recipient_username
  from public.profiles p
  where p.id = new.recipient_id;

  preview := nullif(btrim(new.body), '');
  if preview is null then
    preview := coalesce(new.attachment_title, 'Shared something with you');
  end if;

  if recipient_username is not null
     and new.body is not null
     and lower(recipient_username) = any(
       coalesce(
         (
           select array_agg(distinct lower(m[1]))
           from regexp_matches(
             lower(new.body),
             '@([a-z0-9._-]+)',
             'g'
           ) as m
         ),
         array[]::text[]
       )
     )
     and private.mention_notifications_enabled(new.recipient_id)
  then
    is_mention := true;
  end if;

  insert into public.social_inbox_events(
    recipient_id,
    kind,
    title,
    message,
    entity_type,
    entity_id
  )
  values (
    new.recipient_id,
    case when is_mention then 'mention' else 'message' end,
    case
      when is_mention then 'You were mentioned'
      else coalesce(sender_name, 'A friend')
    end,
    case
      when is_mention then '@' || coalesce(sender_name, 'A friend') || ' mentioned you in a message.'
      else left(preview, 240)
    end,
    'direct_conversation',
    new.conversation_id
  );

  return new;
end;
$$;

-- Group chat notifications + @mentions / @everyone.
create or replace function private.after_community_group_message_notify()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  group_name text;
  sender_label text;
  sender_role text;
  mention_tokens text[];
  everyone_tagged boolean := false;
  target record;
  target_mentioned boolean;
  mode text;
begin
  select g.name into group_name
  from public.community_groups g
  where g.id = new.group_id;

  select
    coalesce(nullif(p.username::text, ''), nullif(p.display_name, ''), 'A member')
  into sender_label
  from public.profiles p
  where p.id = new.sender_id;

  sender_role := private.community_group_role(new.group_id, new.sender_id);

  select array_agg(distinct lower(m[1]))
    into mention_tokens
  from regexp_matches(
    lower(new.body),
    '@([a-z0-9._-]+)',
    'g'
  ) as m;

  mention_tokens := coalesce(mention_tokens, array[]::text[]);

  everyone_tagged :=
    (
      'everyone' = any(mention_tokens)
      or 'all' = any(mention_tokens)
      or 'alle' = any(mention_tokens)
    )
    and sender_role in ('owner', 'admin', 'contributor');

  for target in
    select gm.user_id, p.username::text as username
    from public.community_group_members gm
    left join public.profiles p on p.id = gm.user_id
    where gm.group_id = new.group_id
      and gm.user_id <> new.sender_id
  loop
    target_mentioned :=
      everyone_tagged
      or (
        target.username is not null
        and lower(target.username) = any(mention_tokens)
      );

    mode := private.community_group_notification_mode(
      new.group_id,
      target.user_id
    );

    if target_mentioned
       and private.mention_notifications_enabled(target.user_id)
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
      values (
        target.user_id,
        'mention',
        'You were mentioned',
        '@' || coalesce(sender_label, 'A member') ||
          ' mentioned you in ' || coalesce(group_name, 'a group') || '.',
        'community_group_message',
        new.id,
        new.group_id
      );
    elsif mode = 'all' then
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
        target.user_id,
        'group_message',
        coalesce(group_name, 'Group'),
        coalesce(sender_label, 'A member') || ': ' || left(new.body, 220),
        'community_group_message',
        new.id,
        new.group_id
      );
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists community_group_messages_notify
  on public.community_group_messages;
create trigger community_group_messages_notify
after insert on public.community_group_messages
for each row execute function private.after_community_group_message_notify();

create or replace function private.after_community_group_announcement_notify()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  group_name text;
  target record;
  mode text;
begin
  select g.name into group_name
  from public.community_groups g
  where g.id = new.group_id;

  for target in
    select gm.user_id
    from public.community_group_members gm
    where gm.group_id = new.group_id
      and gm.user_id <> new.author_id
  loop
    mode := private.community_group_notification_mode(
      new.group_id,
      target.user_id
    );

    if mode in ('all', 'important') then
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
        target.user_id,
        'group_update',
        coalesce(group_name, 'Group') || ' update',
        left(new.body, 240),
        'community_group_announcement',
        new.id,
        new.group_id
      );
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists community_group_announcements_notify
  on public.community_group_announcements;
create trigger community_group_announcements_notify
after insert on public.community_group_announcements
for each row execute function private.after_community_group_announcement_notify();

create or replace function private.after_community_group_event_notify()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  group_name text;
  target record;
  mode text;
begin
  select g.name into group_name
  from public.community_groups g
  where g.id = new.group_id;

  for target in
    select gm.user_id
    from public.community_group_members gm
    where gm.group_id = new.group_id
      and gm.user_id <> new.creator_id
  loop
    mode := private.community_group_notification_mode(
      new.group_id,
      target.user_id
    );

    if mode in ('all', 'important') then
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
        target.user_id,
        'group_event',
        'New event in ' || coalesce(group_name, 'your group'),
        new.title,
        'community_group_event',
        new.id,
        new.group_id
      );
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists community_group_events_notify
  on public.community_group_events;
create trigger community_group_events_notify
after insert on public.community_group_events
for each row execute function private.after_community_group_event_notify();

create or replace function private.after_community_group_challenge_notify()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  group_name text;
  target record;
  mode text;
begin
  select g.name into group_name
  from public.community_groups g
  where g.id = new.group_id;

  for target in
    select gm.user_id
    from public.community_group_members gm
    where gm.group_id = new.group_id
      and gm.user_id <> new.creator_id
  loop
    mode := private.community_group_notification_mode(
      new.group_id,
      target.user_id
    );

    if mode in ('all', 'important') then
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
        target.user_id,
        'group_challenge',
        'New challenge in ' || coalesce(group_name, 'your group'),
        new.title,
        'community_group_challenge',
        new.id,
        new.group_id
      );
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists community_group_challenges_notify
  on public.community_group_challenges;
create trigger community_group_challenges_notify
after insert on public.community_group_challenges
for each row execute function private.after_community_group_challenge_notify();

revoke all on function private.community_group_role(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.can_create_community_group_content(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.community_group_notification_mode(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.mention_notifications_enabled(uuid)
  from public, anon, authenticated;
revoke all on function private.after_community_group_message_notify()
  from public, anon, authenticated;
revoke all on function private.after_community_group_announcement_notify()
  from public, anon, authenticated;
revoke all on function private.after_community_group_event_notify()
  from public, anon, authenticated;
revoke all on function private.after_community_group_challenge_notify()
  from public, anon, authenticated;
