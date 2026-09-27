-- Follow requests are only meaningful for non-public profiles.
-- Public profiles are followed immediately through profile_follows.

create or replace function private.guard_friend_request()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  allows_requests boolean;
  target_visibility text;
begin
  if tg_op = 'INSERT' then
    if actor is null or actor <> new.sender_id then
      raise exception 'Follow request sender must match authenticated user';
    end if;

    if new.sender_id = new.recipient_id then
      raise exception 'Cannot send a follow request to yourself';
    end if;

    if private.is_blocked(new.recipient_id) then
      raise exception 'Follow request is not available for this user';
    end if;

    if private.are_friends(new.recipient_id) then
      raise exception 'This follow request has already been approved';
    end if;

    select
      s.allow_friend_requests,
      s.profile_visibility
    into
      allows_requests,
      target_visibility
    from public.profile_social_settings s
    where s.user_id = new.recipient_id;

    if coalesce(target_visibility, 'public') = 'public' then
      raise exception 'Public profiles can be followed without a request';
    end if;

    if coalesce(allows_requests, false) is not true then
      raise exception 'This user is not accepting follow requests';
    end if;

    new.status := 'pending';
    new.responded_at := null;
    return new;
  end if;

  if new.sender_id <> old.sender_id
     or new.recipient_id <> old.recipient_id
     or new.message is distinct from old.message
     or new.created_at <> old.created_at then
    raise exception 'Follow request identity fields are immutable';
  end if;

  if old.status <> 'pending' then
    raise exception 'Follow request has already been resolved';
  end if;

  if actor = old.recipient_id
     and new.status in ('accepted','declined') then
    new.responded_at := now();
    return new;
  end if;

  if actor = old.sender_id
     and new.status = 'cancelled' then
    new.responded_at := now();
    return new;
  end if;

  raise exception 'Invalid follow request transition';
end;
$$;

revoke all on function private.guard_friend_request()
from public, anon, authenticated;
