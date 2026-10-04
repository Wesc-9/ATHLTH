-- Replace the obsolete friendship relationship model with Follow / Following.
-- Historical friendship pairs are converted to reciprocal follows before removal.

insert into public.profile_follows (follower_id, following_id, created_at)
select user_a, user_b, created_at
from public.friendships
union all
select user_b, user_a, created_at
from public.friendships
on conflict (follower_id, following_id) do nothing;

-- Old "friends" visibility now means mutual follows.
drop policy if exists "routes_read_allowed"
on public.community_routes;

create policy "routes_read_allowed"
on public.community_routes
for select
to authenticated
using (
  owner_id = (select auth.uid())
  or visibility = 'public'
  or (
    visibility = 'friends'
    and private.are_friends(owner_id)
  )
);

drop policy if exists "route_attempts_select_allowed"
on public.route_attempts;

create policy "route_attempts_select_allowed"
on public.route_attempts
for select
to authenticated
using (
  user_id = (select auth.uid())
  or (
    private.can_view_profile_card(user_id)
    and exists (
      select 1
      from public.community_routes r
      where r.id = route_id
        and (
          r.owner_id = (select auth.uid())
          or r.visibility = 'public'
          or (
            r.visibility = 'friends'
            and private.are_friends(r.owner_id)
          )
        )
    )
  )
);

drop policy if exists "community_events_select_visible"
on public.community_events;

create policy "community_events_select_visible"
on public.community_events
for select
to authenticated
using (
  creator_id = (select auth.uid())
  or visibility = 'public'
  or (
    visibility = 'friends'
    and private.are_friends(creator_id)
  )
);

-- Ghost challenges also use mutual follows instead of the removed table.
create or replace function private.can_send_ghost_race(
  p_sender uuid,
  p_recipient uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and p_sender = (select auth.uid())
    and p_sender <> p_recipient
    and exists (
      select 1
      from public.profile_follows f
      where f.follower_id = p_sender
        and f.following_id = p_recipient
    )
    and exists (
      select 1
      from public.profile_follows f
      where f.follower_id = p_recipient
        and f.following_id = p_sender
    )
    and not exists (
      select 1
      from public.user_blocks b
      where
        (b.blocker_id = p_sender and b.blocked_id = p_recipient)
        or
        (b.blocker_id = p_recipient and b.blocked_id = p_sender)
    )
    and coalesce(
      (
        select p.allow_challenge_invites
        from public.profile_social_settings p
        where p.user_id = p_recipient
      ),
      'friends'
    ) <> 'nobody';
$$;

revoke all on function private.can_send_ghost_race(uuid, uuid)
from public, anon;
grant execute on function private.can_send_ghost_race(uuid, uuid)
to authenticated;

-- Remove the original block trigger/function that still touched friendships.
drop trigger if exists user_blocks_after_insert
on public.user_blocks;
drop function if exists private.after_block_created();

-- Keep block cleanup behavior using only the Follow / Following model.
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

drop table if exists public.friendships;
