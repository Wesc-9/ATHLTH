-- Remove the obsolete friendships relationship model.
-- Existing friendship pairs are migrated to reciprocal profile follows first.
-- The active product relationship is Follow / Following; mutual follows replace friends.

insert into public.profile_follows (follower_id, following_id, created_at)
select user_a, user_b, created_at
from public.friendships
union all
select user_b, user_a, created_at
from public.friendships
on conflict (follower_id, following_id) do nothing;

-- Remove the original block trigger/function that still referenced friendships.
drop trigger if exists user_blocks_after_insert on public.user_blocks;
drop function if exists private.after_block_created();

-- Keep the current block cleanup behavior, but only against the follow model.
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
