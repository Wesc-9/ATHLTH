-- Privacy-first social defaults and RPC hardening.

alter table public.profile_social_settings
  alter column share_training_presence set default false,
  alter column share_performance_stats set default false,
  alter column share_trophy_cabinet set default false,
  alter column share_goals set default false,
  alter column share_recent_activity set default false,
  alter column share_running_prs set default false,
  alter column share_strength_prs set default false,
  alter column share_workout_totals set default false;

update public.profile_social_settings
set
  share_training_presence = false,
  share_performance_stats = false,
  share_trophy_cabinet = false,
  share_goals = false,
  share_recent_activity = false,
  share_running_prs = false,
  share_strength_prs = false,
  share_workout_totals = false,
  updated_at = now();

create or replace function private.get_or_create_direct_conversation_impl(other_user uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $function$
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
    insert into public.direct_conversations(user_a, user_b, request_status, requested_by)
    values (actor, other_user, 'accepted', null)
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
    insert into public.direct_conversations(user_a, user_b, request_status, requested_by)
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

  if existing.request_status = 'declined' then
    raise exception 'This message request was declined';
  end if;

  return existing.id;
end;
$function$;

create or replace function private.is_username_available_impl(candidate text)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $function$
declare
  actor uuid := auth.uid();
  cleaned text := lower(trim(candidate));
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if cleaned is null
     or char_length(cleaned) < 3
     or char_length(cleaned) > 30
     or cleaned !~ '^[a-z0-9_.]+$' then
    return false;
  end if;

  return not exists (
    select 1
    from public.profiles p
    where lower(p.username) = cleaned
      and p.id <> actor
  );
end;
$function$;

create or replace function private.respond_to_direct_message_request_impl(
  conversation_id uuid,
  accept_request boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $function$
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
      recipient_id, kind, title, message, entity_type, entity_id
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
$function$;

revoke all on function private.get_or_create_direct_conversation_impl(uuid) from public;
revoke all on function private.is_username_available_impl(text) from public;
revoke all on function private.respond_to_direct_message_request_impl(uuid, boolean) from public;

grant usage on schema private to authenticated;
grant execute on function private.get_or_create_direct_conversation_impl(uuid) to authenticated;
grant execute on function private.is_username_available_impl(text) to authenticated;
grant execute on function private.respond_to_direct_message_request_impl(uuid, boolean) to authenticated;

create or replace function public.get_or_create_direct_conversation(other_user uuid)
returns uuid
language sql
security invoker
set search_path = pg_catalog
as $function$
  select private.get_or_create_direct_conversation_impl(other_user);
$function$;

create or replace function public.is_username_available(candidate text)
returns boolean
language sql
stable
security invoker
set search_path = pg_catalog
as $function$
  select private.is_username_available_impl(candidate);
$function$;

create or replace function public.respond_to_direct_message_request(
  conversation_id uuid,
  accept_request boolean
)
returns void
language sql
security invoker
set search_path = pg_catalog
as $function$
  select private.respond_to_direct_message_request_impl(conversation_id, accept_request);
$function$;

revoke all on function public.get_or_create_direct_conversation(uuid) from public;
revoke all on function public.is_username_available(text) from public;
revoke all on function public.respond_to_direct_message_request(uuid, boolean) from public;

grant execute on function public.get_or_create_direct_conversation(uuid) to authenticated;
grant execute on function public.is_username_available(text) to authenticated;
grant execute on function public.respond_to_direct_message_request(uuid, boolean) to authenticated;
