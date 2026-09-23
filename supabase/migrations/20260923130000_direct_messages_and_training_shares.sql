-- ATHLTH direct messaging and shareable training objects.
-- 1:1 messaging is restricted to accepted friends and respects user blocks.

create table if not exists public.direct_conversations (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_message_at timestamptz,
  check (user_a <> user_b)
);

create unique index if not exists direct_conversations_pair_idx
  on public.direct_conversations (
    least(user_a::text, user_b::text),
    greatest(user_a::text, user_b::text)
  );

create index if not exists direct_conversations_user_a_idx
  on public.direct_conversations(user_a, last_message_at desc);

create index if not exists direct_conversations_user_b_idx
  on public.direct_conversations(user_b, last_message_at desc);

create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.direct_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text,
  attachment_kind text check (
    attachment_kind is null or
    attachment_kind in ('workout','training_plan','running_workout','route','challenge')
  ),
  attachment_title text,
  attachment_subtitle text,
  attachment_payload text,
  share_version integer not null default 1 check (share_version > 0),
  source_object_id uuid,
  source_owner_id uuid,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  deleted_at timestamptz,
  check (sender_id <> recipient_id),
  check (
    coalesce(char_length(btrim(body)), 0) > 0
    or attachment_kind is not null
  ),
  check (body is null or char_length(body) <= 4000),
  check (attachment_title is null or char_length(attachment_title) <= 180),
  check (attachment_subtitle is null or char_length(attachment_subtitle) <= 500),
  check (attachment_payload is null or octet_length(attachment_payload) <= 1048576)
);

create index if not exists direct_messages_conversation_idx
  on public.direct_messages(conversation_id, created_at desc);

create index if not exists direct_messages_recipient_unread_idx
  on public.direct_messages(recipient_id, created_at desc)
  where read_at is null and deleted_at is null;

alter table public.direct_conversations enable row level security;
alter table public.direct_messages enable row level security;

revoke all on table public.direct_conversations from anon, authenticated;
revoke all on table public.direct_messages from anon, authenticated;

grant select on table public.direct_conversations to authenticated;
grant select, insert, update on table public.direct_messages to authenticated;

drop policy if exists direct_conversations_select_participant
  on public.direct_conversations;
create policy direct_conversations_select_participant
  on public.direct_conversations
  for select
  to authenticated
  using (
    (select auth.uid()) = user_a
    or (select auth.uid()) = user_b
  );

drop policy if exists direct_messages_select_participant
  on public.direct_messages;
create policy direct_messages_select_participant
  on public.direct_messages
  for select
  to authenticated
  using (
    (select auth.uid()) = sender_id
    or (select auth.uid()) = recipient_id
  );

drop policy if exists direct_messages_insert_sender
  on public.direct_messages;
create policy direct_messages_insert_sender
  on public.direct_messages
  for insert
  to authenticated
  with check (
    sender_id = (select auth.uid())
    and recipient_id <> (select auth.uid())
    and private.are_friends(recipient_id)
    and not private.is_blocked(recipient_id)
    and exists (
      select 1
      from public.direct_conversations c
      where c.id = conversation_id
        and (
          (c.user_a = sender_id and c.user_b = recipient_id)
          or
          (c.user_b = sender_id and c.user_a = recipient_id)
        )
    )
  );

drop policy if exists direct_messages_update_recipient
  on public.direct_messages;
create policy direct_messages_update_recipient
  on public.direct_messages
  for update
  to authenticated
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));

create or replace function public.get_or_create_direct_conversation(other_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  actor uuid := auth.uid();
  existing_id uuid;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if other_user is null or other_user = actor then
    raise exception 'Invalid conversation participant';
  end if;

  if not private.are_friends(other_user) then
    raise exception 'Direct messages are only available between friends';
  end if;

  if private.is_blocked(other_user) then
    raise exception 'Messaging is unavailable for this user';
  end if;

  select c.id
    into existing_id
  from public.direct_conversations c
  where (c.user_a = actor and c.user_b = other_user)
     or (c.user_a = other_user and c.user_b = actor)
  limit 1;

  if existing_id is not null then
    return existing_id;
  end if;

  begin
    insert into public.direct_conversations(user_a, user_b)
    values (actor, other_user)
    returning id into existing_id;
  exception
    when unique_violation then
      select c.id
        into existing_id
      from public.direct_conversations c
      where (c.user_a = actor and c.user_b = other_user)
         or (c.user_a = other_user and c.user_b = actor)
      limit 1;
  end;

  return existing_id;
end;
$$;

revoke all on function public.get_or_create_direct_conversation(uuid)
  from public, anon;
grant execute on function public.get_or_create_direct_conversation(uuid)
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

  if not private.are_friends(new.recipient_id) then
    raise exception 'Direct messages are only available between friends';
  end if;

  if private.is_blocked(new.recipient_id) then
    raise exception 'Messaging is unavailable for this user';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_direct_message_insert()
  from public, anon, authenticated;

drop trigger if exists direct_messages_guard_insert
  on public.direct_messages;
create trigger direct_messages_guard_insert
  before insert on public.direct_messages
  for each row execute function private.guard_direct_message_insert();

create or replace function private.guard_direct_message_update()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if old.recipient_id <> auth.uid() then
    raise exception 'Only the recipient can mark a message as read';
  end if;

  if new.id is distinct from old.id
     or new.conversation_id is distinct from old.conversation_id
     or new.sender_id is distinct from old.sender_id
     or new.recipient_id is distinct from old.recipient_id
     or new.body is distinct from old.body
     or new.attachment_kind is distinct from old.attachment_kind
     or new.attachment_title is distinct from old.attachment_title
     or new.attachment_subtitle is distinct from old.attachment_subtitle
     or new.attachment_payload is distinct from old.attachment_payload
     or new.share_version is distinct from old.share_version
     or new.source_object_id is distinct from old.source_object_id
     or new.source_owner_id is distinct from old.source_owner_id
     or new.created_at is distinct from old.created_at
     or new.deleted_at is distinct from old.deleted_at then
    raise exception 'Message content is immutable';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_direct_message_update()
  from public, anon, authenticated;

drop trigger if exists direct_messages_guard_update
  on public.direct_messages;
create trigger direct_messages_guard_update
  before update on public.direct_messages
  for each row execute function private.guard_direct_message_update();

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
      'workout_joined',
      'message'
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
begin
  update public.direct_conversations
  set
    last_message_at = new.created_at,
    updated_at = now()
  where id = new.conversation_id;

  select coalesce(p.display_name, p.username::text, 'A friend')
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
    'message',
    coalesce(sender_name, 'A friend'),
    left(preview, 240),
    'direct_conversation',
    new.conversation_id
  );

  return new;
end;
$$;

revoke all on function private.after_direct_message_insert()
  from public, anon, authenticated;

drop trigger if exists direct_messages_after_insert
  on public.direct_messages;
create trigger direct_messages_after_insert
  after insert on public.direct_messages
  for each row execute function private.after_direct_message_insert();
