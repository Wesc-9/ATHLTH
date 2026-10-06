-- First contact should be an actual request only when the first item is sent.
-- Opening a non-mutual thread may create a pending conversation row before
-- either athlete sends anything. The first sender claims that empty pending
-- row atomically, and the single request may be text or one share attachment.

create or replace function private.guard_direct_message_insert()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  actor uuid := auth.uid();
  c public.direct_conversations%rowtype;
  target_setting text;
  existing_count integer;
begin
  if actor is null or new.sender_id <> actor then
    raise exception 'Message sender must match authenticated user';
  end if;

  select *
    into c
  from public.direct_conversations
  where id = new.conversation_id
  for update;

  if c.id is null then
    raise exception 'Conversation not found';
  end if;

  if not (
    (c.user_a = new.sender_id and c.user_b = new.recipient_id)
    or
    (c.user_b = new.sender_id and c.user_a = new.recipient_id)
  ) then
    raise exception 'Message participants do not match conversation';
  end if;

  if private.is_blocked(new.recipient_id) then
    raise exception 'Messaging is unavailable for this user';
  end if;

  if c.request_status = 'declined' then
    raise exception 'This message request was declined';
  end if;

  if c.request_status = 'accepted' then
    return new;
  end if;

  select count(*)
    into existing_count
  from public.direct_messages m
  where m.conversation_id = c.id;

  if existing_count > 0 then
    if c.requested_by <> actor then
      raise exception 'Accept this message request before replying';
    end if;

    raise exception 'Wait for this message request to be accepted before sending another message';
  end if;

  if coalesce(char_length(btrim(new.body)), 0) = 0
     and new.attachment_kind is null then
    raise exception 'A message request must include text or a shared item';
  end if;

  select s.allow_direct_messages
    into target_setting
  from public.profile_social_settings s
  where s.user_id = new.recipient_id;

  if coalesce(target_setting, 'requests') <> 'requests' then
    raise exception 'This user no longer accepts message requests';
  end if;

  if c.requested_by is distinct from actor then
    update public.direct_conversations
    set
      requested_by = actor,
      responded_at = null,
      updated_at = now()
    where id = c.id;
  end if;

  return new;
end;
$$;

revoke all on function private.guard_direct_message_insert()
from public, anon, authenticated;
