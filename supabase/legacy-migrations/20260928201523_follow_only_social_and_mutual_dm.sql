-- Follow-only social model:
-- 1) legacy "friends" authorization now means mutual follow,
-- 2) private profiles can only be followed through an approved follow request,
-- 3) mutual followers can message directly,
-- 4) a pending/declined message request is promoted when the users become mutual followers.

create or replace function private.are_friends(other_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and other_user is not null
    and other_user <> (select auth.uid())
    and exists (
      select 1
      from public.profile_follows f
      where f.follower_id = (select auth.uid())
        and f.following_id = other_user
    )
    and exists (
      select 1
      from public.profile_follows f
      where f.follower_id = other_user
        and f.following_id = (select auth.uid())
    );
$$;

revoke all on function private.are_friends(uuid)
from public, anon, authenticated;

drop policy if exists "users can follow public profiles from their own account"
on public.profile_follows;

create policy "users can follow public profiles from their own account"
on public.profile_follows
for insert
to authenticated
with check (
  (select auth.uid()) = follower_id
  and follower_id <> following_id
  and coalesce(
    (
      select s.profile_visibility = 'public'
      from public.profile_social_settings s
      where s.user_id = following_id
    ),
    false
  )
);

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
      raise exception 'This message request was declined';
    end if;

    return existing.id;
  end if;

  if mutual_follow then
    insert into public.direct_conversations(
      user_a,
      user_b,
      request_status,
      requested_by
    )
    values (
      actor,
      other_user,
      'accepted',
      null
    )
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
      user_a,
      user_b,
      request_status,
      requested_by
    )
    values (
      actor,
      other_user,
      'pending',
      actor
    )
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
    raise exception 'This message request was declined';
  end if;

  return existing.id;
end;
$$;

revoke all on function private.get_or_create_direct_conversation_impl(uuid)
from public, anon, authenticated;
