-- ATHLTH message requests for non-friends.
-- Existing friend conversations remain accepted. Non-friends may send exactly
-- one text-only request when the recipient allows message requests.

alter table public.profile_social_settings
  alter column allow_direct_messages set default 'requests';

alter table public.profile_social_settings
  drop constraint if exists profile_social_settings_allow_direct_messages_check;

alter table public.profile_social_settings
  add constraint profile_social_settings_allow_direct_messages_check
  check (allow_direct_messages in ('friends', 'requests', 'nobody'));

alter table public.direct_conversations
  add column if not exists request_status text not null default 'accepted',
  add column if not exists requested_by uuid references auth.users(id) on delete set null,
  add column if not exists responded_at timestamptz;

alter table public.direct_conversations
  drop constraint if exists direct_conversations_request_status_check;

alter table public.direct_conversations
  add constraint direct_conversations_request_status_check
  check (request_status in ('pending', 'accepted', 'declined'));

alter table public.direct_conversations
  drop constraint if exists direct_conversations_requested_by_participant_check;

alter table public.direct_conversations
  add constraint direct_conversations_requested_by_participant_check
  check (
    requested_by is null
    or requested_by = user_a
    or requested_by = user_b
  );

alter table public.direct_conversations
  drop constraint if exists direct_conversations_requester_required_check;

alter table public.direct_conversations
  add constraint direct_conversations_requester_required_check
  check (
    request_status = 'accepted'
    or requested_by is not null
  );

create index if not exists direct_conversations_request_status_idx
  on public.direct_conversations(request_status, requested_by, last_message_at desc);

drop policy if exists direct_messages_insert_sender
  on public.direct_messages;

create policy direct_messages_insert_sender
  on public.direct_messages
  for insert
  to authenticated
  with check (
    sender_id = (select auth.uid())
    and recipient_id <> (select auth.uid())
    and exists (
      select 1
      from public.direct_conversations c
      where c.id = conversation_id
        and (
          (c.user_a = sender_id and c.user_b = recipient_id)
          or
          (c.user_b = sender_id and c.user_a = recipient_id)
        )
        and (
          c.request_status = 'accepted'
          or (
            c.request_status = 'pending'
            and c.requested_by = (select auth.uid())
            and attachment_kind is null
            and coalesce(char_length(btrim(body)), 0) > 0
            and not exists (
              select 1
              from public.direct_messages existing
              where existing.conversation_id = c.id
            )
          )
        )
    )
  );

create or replace function public.get_or_create_direct_conversation(other_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  actor uuid := auth.uid();
  existing public.direct_conversations%rowtype;
  target_setting text;
  friend_state boolean;
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

  select c.*
    into existing
  from public.direct_conversations c
  where (c.user_a = actor and c.user_b = other_user)
     or (c.user_a = other_user and c.user_b = actor)
  limit 1;

  if existing.id is not null then
    if existing.request_status = 'declined' then
      raise exception 'This message request was declined';
    end if;
    return existing.id;
  end if;

  friend_state := private.are_friends(other_user);

  if friend_state then
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

  if coalesce(target_setting, 'friends') <> 'requests' then
    raise exception 'This user only accepts messages from friends';
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

  if existing.request_status = 'declined' then
    raise exception 'This message request was declined';
  end if;

  return existing.id;
end;
$$;

revoke all on function public.get_or_create_direct_conversation(uuid)
  from public, anon;
grant execute on function public.get_or_create_direct_conversation(uuid)
  to authenticated;

create or replace function public.respond_to_direct_message_request(
  conversation_id uuid,
  accept_request boolean
)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  actor uuid := auth.uid();
  c public.direct_conversations%rowtype;
  requester_name text;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  select *
    into c
  from public.direct_conversations
  where id = conversation_id
  for update;

  if c.id is null then
    raise exception 'Conversation not found';
  end if;

  if c.request_status <> 'pending' then
    raise exception 'Message request is no longer pending';
  end if;

  if c.requested_by = actor then
    raise exception 'You cannot respond to your own message request';
  end if;

  if actor <> c.user_a and actor <> c.user_b then
    raise exception 'You are not part of this conversation';
  end if;

  if accept_request and private.is_blocked(c.requested_by) then
    raise exception 'Messaging is unavailable for this user';
  end if;

  update public.direct_conversations
  set
    request_status = case when accept_request then 'accepted' else 'declined' end,
    responded_at = now(),
    updated_at = now()
  where id = c.id;

  update public.social_inbox_events
  set read_at = coalesce(read_at, now())
  where recipient_id = actor
    and kind = 'message_request'
    and entity_type = 'direct_conversation'
    and entity_id = c.id;

  if accept_request then
    select coalesce(p.display_name, p.username::text, 'Someone')
      into requester_name
    from public.profiles p
    where p.id = actor;

    insert into public.social_inbox_events(
      recipient_id,
      kind,
      title,
      message,
      entity_type,
      entity_id
    )
    values (
      c.requested_by,
      'message_request_accepted',
      'Message request accepted',
      coalesce(requester_name, 'Someone') || ' accepted your message request.',
      'direct_conversation',
      c.id
    );
  end if;
end;
$$;

revoke all on function public.respond_to_direct_message_request(uuid, boolean)
  from public, anon;
grant execute on function public.respond_to_direct_message_request(uuid, boolean)
  to authenticated;

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
  where id = new.conversation_id;

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

  if c.requested_by <> actor then
    raise exception 'Accept this message request before replying';
  end if;

  if new.attachment_kind is not null then
    raise exception 'Training items cannot be attached to a message request';
  end if;

  if coalesce(char_length(btrim(new.body)), 0) = 0 then
    raise exception 'A message request must include text';
  end if;

  select count(*)
    into existing_count
  from public.direct_messages m
  where m.conversation_id = c.id;

  if existing_count > 0 then
    raise exception 'Wait for this message request to be accepted before sending another message';
  end if;

  select s.allow_direct_messages
    into target_setting
  from public.profile_social_settings s
  where s.user_id = new.recipient_id;

  if coalesce(target_setting, 'friends') <> 'requests' then
    raise exception 'This user no longer accepts message requests';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_direct_message_insert()
  from public, anon, authenticated;

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
      'message_request_accepted'
    )
  );

create or replace function private.after_direct_message_insert()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  sender_name text;
  preview text;
  conversation_state text;
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

  select coalesce(p.display_name, p.username::text, 'Someone')
    into sender_name
  from public.profiles p
  where p.id = new.sender_id;

  preview := nullif(btrim(new.body), '');
  if preview is null then
    preview := coalesce(new.attachment_title, 'Shared something with you');
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
      when conversation_state = 'pending' then 'message_request'
      else 'message'
    end,
    case
      when conversation_state = 'pending'
        then 'Message request from ' || coalesce(sender_name, 'Someone')
      else coalesce(sender_name, 'A friend')
    end,
    left(preview, 240),
    'direct_conversation',
    new.conversation_id
  );

  return new;
end;
$$;

revoke all on function private.after_direct_message_insert()
  from public, anon, authenticated;
