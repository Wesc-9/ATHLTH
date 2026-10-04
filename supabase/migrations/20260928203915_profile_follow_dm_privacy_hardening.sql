alter table public.profile_social_settings
  add column if not exists gear_visibility text not null default 'private'
    check (gear_visibility in ('private','friends','public')),
  add column if not exists share_gear boolean not null default false;

comment on column public.profile_social_settings.gear_visibility is
  'Audience for profile gear. friends means approved followers.';
comment on column public.profile_social_settings.share_gear is
  'Whether gear is exposed on the social profile.';

create or replace function private.can_view_social_section(
  owner_id uuid,
  section_name text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) = owner_id
    or (
      (select auth.uid()) is not null
      and not private.is_blocked(owner_id)
      and (
        coalesce((
          select case section_name
            when 'presence' then s.training_presence_visibility
            when 'performance' then s.performance_stats_visibility
            when 'trophies' then s.trophy_cabinet_visibility
            when 'activity' then s.recent_activity_visibility
            when 'goals' then s.goals_visibility
            when 'gear' then s.gear_visibility
            when 'running_prs' then s.running_prs_visibility
            when 'strength_prs' then s.strength_prs_visibility
            when 'workout_totals' then s.performance_stats_visibility
            else 'private'
          end
          from public.profile_social_settings s
          where s.user_id = owner_id
        ), 'private') = 'public'
        or (
          coalesce((
            select case section_name
              when 'presence' then s.training_presence_visibility
              when 'performance' then s.performance_stats_visibility
              when 'trophies' then s.trophy_cabinet_visibility
              when 'activity' then s.recent_activity_visibility
              when 'goals' then s.goals_visibility
              when 'gear' then s.gear_visibility
              when 'running_prs' then s.running_prs_visibility
              when 'strength_prs' then s.strength_prs_visibility
              when 'workout_totals' then s.performance_stats_visibility
              else 'private'
            end
            from public.profile_social_settings s
            where s.user_id = owner_id
          ), 'private') = 'friends'
          and private.is_following(owner_id)
        )
      )
    );
$$;

revoke all on function private.can_view_social_section(uuid, text)
from public, anon, authenticated;

drop policy if exists "authenticated users can view profile gear"
on public.profile_gear;
drop policy if exists "profile gear select allowed"
on public.profile_gear;

create policy "profile gear select allowed"
on public.profile_gear
for select
to authenticated
using (private.can_view_social_section(user_id, 'gear'));

drop policy if exists "users can view their own gear details"
on public.profile_gear_details;
drop policy if exists "profile gear details select allowed"
on public.profile_gear_details;

create policy "profile gear details select allowed"
on public.profile_gear_details
for select
to authenticated
using (private.can_view_social_section(user_id, 'gear'));

create table if not exists public.social_profile_goals (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  category text not null,
  status text not null check (status in ('active','paused','completed')),
  progress double precision not null default 0
    check (progress >= 0 and progress <= 1),
  is_primary boolean not null default false,
  deadline timestamptz,
  visibility text not null
    check (visibility in ('friends','public')),
  updated_at timestamptz not null default now()
);

create index if not exists social_profile_goals_user_idx
on public.social_profile_goals(user_id, is_primary desc, updated_at desc);

alter table public.social_profile_goals enable row level security;

grant select, insert, update, delete
on public.social_profile_goals
to authenticated;

drop policy if exists "social profile goals select allowed"
on public.social_profile_goals;
create policy "social profile goals select allowed"
on public.social_profile_goals
for select
to authenticated
using (
  private.can_view_social_section(user_id, 'goals')
  and (
    (select auth.uid()) = user_id
    or visibility = 'public'
    or (
      visibility = 'friends'
      and private.is_following(user_id)
    )
  )
);

drop policy if exists "social profile goals insert own"
on public.social_profile_goals;
create policy "social profile goals insert own"
on public.social_profile_goals
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "social profile goals update own"
on public.social_profile_goals;
create policy "social profile goals update own"
on public.social_profile_goals
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "social profile goals delete own"
on public.social_profile_goals;
create policy "social profile goals delete own"
on public.social_profile_goals
for delete
to authenticated
using ((select auth.uid()) = user_id);

comment on table public.social_profile_goals is
  'Minimal social snapshots of goals explicitly shared by their owner.';

comment on table public.friend_requests is
  'Legacy table name retained for compatibility; rows represent profile follow requests.';

create or replace function private.after_friend_request_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  sender_name text;
  recipient_name text;
begin
  if tg_op = 'INSERT' then
    select coalesce(display_name, username::text, 'Someone')
      into sender_name
    from public.social_profile_cards
    where user_id = new.sender_id;

    insert into public.social_inbox_events (
      recipient_id, kind, title, message, entity_type, entity_id
    )
    values (
      new.recipient_id,
      'follow_request',
      'New follow request',
      coalesce(sender_name, 'Someone') || ' wants to follow you on ATHLTH.',
      'follow_request',
      new.id
    );
    return new;
  end if;

  if old.status = 'pending' and new.status <> 'pending' then
    update public.social_inbox_events
    set read_at = coalesce(read_at, now())
    where recipient_id = new.recipient_id
      and kind in ('friend_request','follow_request')
      and entity_id = new.id;
  end if;

  if old.status = 'pending' and new.status = 'accepted' then
    insert into public.profile_follows (follower_id, following_id)
    values (new.sender_id, new.recipient_id)
    on conflict (follower_id, following_id) do nothing;

    select coalesce(display_name, username::text, 'This athlete')
      into recipient_name
    from public.social_profile_cards
    where user_id = new.recipient_id;

    insert into public.social_inbox_events (
      recipient_id, kind, title, message, entity_type, entity_id
    )
    values (
      new.sender_id,
      'follow_accepted',
      'Follow request accepted',
      coalesce(recipient_name, 'This athlete') || ' accepted your follow request.',
      'follow_request',
      new.id
    );
  end if;

  return new;
end;
$$;

revoke all on function private.after_friend_request_change()
from public, anon, authenticated;

create or replace function private.get_or_create_direct_conversation_impl(
  other_user uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  existing public.direct_conversations%rowtype;
  target_setting text;
  mutual_follow boolean;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if other_user is null or other_user = actor then
    raise exception 'Invalid conversation participant';
  end if;

  if private.is_blocked(other_user) then
    raise exception 'Messaging is unavailable for this user';
  end if;

  mutual_follow := private.are_friends(other_user);

  select c.*
    into existing
  from public.direct_conversations c
  where (c.user_a = actor and c.user_b = other_user)
     or (c.user_a = other_user and c.user_b = actor)
  limit 1;

  if existing.id is not null then
    if mutual_follow and existing.request_status <> 'accepted' then
      update public.direct_conversations
      set
        request_status = 'accepted',
        requested_by = null,
        responded_at = coalesce(responded_at, now()),
        updated_at = now()
      where id = existing.id;
      return existing.id;
    end if;

    if existing.request_status = 'declined' then
      if existing.requested_by is not null
         and actor <> existing.requested_by then
        update public.direct_conversations
        set
          request_status = 'accepted',
          requested_by = null,
          responded_at = now(),
          updated_at = now()
        where id = existing.id;
        return existing.id;
      end if;

      raise exception 'This message request was declined';
    end if;

    return existing.id;
  end if;

  if mutual_follow then
    insert into public.direct_conversations(
      user_a, user_b, request_status, requested_by
    )
    values (actor, other_user, 'accepted', null)
    returning id into existing.id;
    return existing.id;
  end if;

  select s.allow_direct_messages
    into target_setting
  from public.profile_social_settings s
  where s.user_id = other_user;

  if coalesce(target_setting, 'requests') = 'nobody' then
    raise exception 'This user is not accepting messages';
  end if;

  if coalesce(target_setting, 'requests') = 'friends' then
    raise exception 'This user only accepts messages from mutual followers';
  end if;

  begin
    insert into public.direct_conversations(
      user_a, user_b, request_status, requested_by
    )
    values (actor, other_user, 'pending', actor)
    returning id into existing.id;
  exception
    when unique_violation then
      select c.*
        into existing
      from public.direct_conversations c
      where (c.user_a = actor and c.user_b = other_user)
         or (c.user_a = other_user and c.user_b = actor)
      limit 1;
  end;

  if private.are_friends(other_user)
     and existing.request_status <> 'accepted' then
    update public.direct_conversations
    set
      request_status = 'accepted',
      requested_by = null,
      responded_at = coalesce(responded_at, now()),
      updated_at = now()
    where id = existing.id;
  elsif existing.request_status = 'declined' then
    if existing.requested_by is not null
       and actor <> existing.requested_by then
      update public.direct_conversations
      set
        request_status = 'accepted',
        requested_by = null,
        responded_at = now(),
        updated_at = now()
      where id = existing.id;
    else
      raise exception 'This message request was declined';
    end if;
  end if;

  return existing.id;
end;
$$;

revoke all on function private.get_or_create_direct_conversation_impl(uuid)
from public, anon, authenticated;

create or replace function private.after_user_block_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.profile_follows
  where (follower_id = new.blocker_id and following_id = new.blocked_id)
     or (follower_id = new.blocked_id and following_id = new.blocker_id);

  delete from public.friendships
  where (user_a = least(new.blocker_id, new.blocked_id)
     and user_b = greatest(new.blocker_id, new.blocked_id));

  update public.friend_requests
  set status = 'cancelled'
  where sender_id = new.blocker_id
    and recipient_id = new.blocked_id
    and status = 'pending';

  update public.friend_requests
  set status = 'declined'
  where sender_id = new.blocked_id
    and recipient_id = new.blocker_id
    and status = 'pending';

  update public.direct_conversations
  set
    request_status = 'declined',
    requested_by = new.blocked_id,
    responded_at = now(),
    updated_at = now()
  where (user_a = new.blocker_id and user_b = new.blocked_id)
     or (user_a = new.blocked_id and user_b = new.blocker_id);

  update public.social_inbox_events
  set read_at = coalesce(read_at, now())
  where recipient_id = new.blocker_id
    and (
      (entity_type = 'direct_conversation'
       and entity_id in (
         select id
         from public.direct_conversations
         where (user_a = new.blocker_id and user_b = new.blocked_id)
            or (user_a = new.blocked_id and user_b = new.blocker_id)
       ))
      or
      (entity_type in ('friend_request','follow_request')
       and entity_id in (
         select id
         from public.friend_requests
         where (sender_id = new.blocker_id and recipient_id = new.blocked_id)
            or (sender_id = new.blocked_id and recipient_id = new.blocker_id)
       ))
    );

  return new;
end;
$$;

revoke all on function private.after_user_block_cleanup()
from public, anon, authenticated;

drop trigger if exists user_blocks_cleanup_relationships
on public.user_blocks;

create trigger user_blocks_cleanup_relationships
after insert on public.user_blocks
for each row execute function private.after_user_block_cleanup();

drop policy if exists direct_conversations_select_participant
on public.direct_conversations;

create policy direct_conversations_select_participant
on public.direct_conversations
for select
to authenticated
using (
  (
    (select auth.uid()) = user_a
    or (select auth.uid()) = user_b
  )
  and not private.is_blocked(
    case
      when (select auth.uid()) = user_a then user_b
      else user_a
    end
  )
);

drop policy if exists direct_messages_select_participant
on public.direct_messages;

create policy direct_messages_select_participant
on public.direct_messages
for select
to authenticated
using (
  (
    (select auth.uid()) = sender_id
    or (select auth.uid()) = recipient_id
  )
  and not private.is_blocked(
    case
      when (select auth.uid()) = sender_id then recipient_id
      else sender_id
    end
  )
);
