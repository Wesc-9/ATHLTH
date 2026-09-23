-- ATHLTH direct-message privacy control.

alter table public.profile_social_settings
  add column if not exists allow_direct_messages text not null default 'friends';

alter table public.profile_social_settings
  drop constraint if exists profile_social_settings_allow_direct_messages_check;

alter table public.profile_social_settings
  add constraint profile_social_settings_allow_direct_messages_check
  check (allow_direct_messages in ('friends', 'nobody'));

create or replace function public.get_or_create_direct_conversation(other_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  actor uuid := auth.uid();
  existing_id uuid;
  target_setting text;
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

  select s.allow_direct_messages
    into target_setting
  from public.profile_social_settings s
  where s.user_id = other_user;

  if coalesce(target_setting, 'friends') = 'nobody' then
    raise exception 'This user is not accepting direct messages';
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

  select s.allow_direct_messages
    into target_setting
  from public.profile_social_settings s
  where s.user_id = new.recipient_id;

  if coalesce(target_setting, 'friends') = 'nobody' then
    raise exception 'This user is not accepting direct messages';
  end if;

  return new;
end;
$$;
