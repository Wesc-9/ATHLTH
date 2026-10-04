-- Preserve the existing message-request lifecycle while adding @mentions.
-- Pending conversations must always emit message_request, never mention.

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
  conversation_state text;
  is_mention boolean := false;
begin
  update public.direct_conversations
  set
    last_message_at = new.created_at,
    updated_at = now()
  where id = new.conversation_id;

  select c.request_status
    into conversation_state
  from public.direct_conversations c
  where c.id = new.conversation_id;

  select
    coalesce(nullif(p.display_name, ''), nullif(p.username::text, ''), 'Someone')
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

  if conversation_state = 'accepted'
     and recipient_username is not null
     and new.body is not null
     and lower(recipient_username) = any(
       coalesce(
         (
           select array_agg(distinct lower(m[1]))
           from regexp_matches(
             lower(new.body),
             '@([a-z0-9_]+)',
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
    case
      when conversation_state = 'pending'
        then 'message_request'
      when is_mention
        then 'mention'
      else 'message'
    end,
    case
      when conversation_state = 'pending'
        then 'Message request from ' || coalesce(sender_name, 'Someone')
      when is_mention
        then 'You were mentioned'
      else coalesce(sender_name, 'A friend')
    end,
    case
      when is_mention
        then coalesce(sender_name, 'A friend') || ' mentioned you in a message.'
      else left(preview, 240)
    end,
    'direct_conversation',
    new.conversation_id
  );

  return new;
end;
$$;

revoke all on function private.after_direct_message_insert()
  from public, anon, authenticated;
