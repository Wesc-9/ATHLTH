-- Social challenge lifecycle + per-person notification grouping for ATHLTH 1.6.1.

alter table public.social_inbox_events
  add column if not exists actor_id uuid references public.profiles(id) on delete set null;

create index if not exists social_inbox_events_recipient_actor_unread_idx
  on public.social_inbox_events(recipient_id, actor_id, created_at desc)
  where read_at is null;

alter table public.social_inbox_events
  drop constraint if exists social_inbox_events_kind_check;

alter table public.social_inbox_events
  add constraint social_inbox_events_kind_check
  check (
    kind = any (
      array[
        'friend_request'::text,
        'friend_accepted'::text,
        'follow_request'::text,
        'follow_accepted'::text,
        'challenge_invite'::text,
        'challenge_result'::text,
        'challenge_accepted'::text,
        'challenge_declined'::text,
        'challenge_withdrawn'::text,
        'reaction'::text,
        'workout_invite'::text,
        'workout_invite_accepted'::text,
        'message'::text,
        'message_request'::text,
        'message_request_accepted'::text,
        'mention'::text,
        'group_message'::text,
        'group_update'::text,
        'group_event'::text,
        'group_challenge'::text,
        'group_invite'::text,
        'group_join_request'::text,
        'group_join_approved'::text
      ]
    )
  );

alter table public.social_challenge_participants
  drop constraint if exists social_challenge_participants_state_check;

alter table public.social_challenge_participants
  add constraint social_challenge_participants_state_check
  check (state in ('creator','invited','accepted','declined','withdrawn'));

create or replace function private.guard_challenge_participant()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  creator uuid;
  target_setting text;
  challenge_title text;
  challenge_sport text;
  challenge_starts_at timestamptz;
begin
  select c.creator_id, c.title, c.sport, c.starts_at
    into creator, challenge_title, challenge_sport, challenge_starts_at
  from public.social_challenges c
  where c.id = coalesce(new.challenge_id, old.challenge_id);

  if creator is null then
    raise exception 'Challenge not found';
  end if;

  if tg_op = 'INSERT' then
    if actor <> creator or new.invited_by <> actor then
      raise exception 'Only the challenge creator can add participants';
    end if;

    if new.user_id = creator then
      if new.state <> 'creator' then
        raise exception 'Creator participant must use creator state';
      end if;
      return new;
    end if;

    if new.state <> 'invited' then
      raise exception 'New participants must start as invited';
    end if;

    if private.is_blocked(new.user_id) then
      raise exception 'Challenge invitation is not available for this user';
    end if;

    select s.allow_challenge_invites into target_setting
    from public.profile_social_settings s
    where s.user_id = new.user_id;

    if coalesce(target_setting, 'nobody') = 'nobody' then
      raise exception 'This user is not accepting challenge invites';
    end if;

    if target_setting = 'friends' and not private.are_friends(new.user_id) then
      raise exception 'This user only accepts challenge invites from friends';
    end if;

    if exists (
      select 1
      from public.social_challenge_participants existing_participant
      join public.social_challenges existing_challenge
        on existing_challenge.id = existing_participant.challenge_id
      where existing_participant.user_id = new.user_id
        and existing_participant.state = 'invited'
        and existing_challenge.creator_id = creator
        and existing_challenge.id <> new.challenge_id
        and existing_challenge.status not in ('completed','cancelled')
        and lower(btrim(existing_challenge.title)) = lower(btrim(challenge_title))
        and existing_challenge.sport = challenge_sport
        and abs(
          extract(
            epoch from (
              existing_challenge.starts_at - challenge_starts_at
            )
          )
        ) <= 900
    ) then
      raise exception 'A matching challenge invite is already pending';
    end if;

    return new;
  end if;

  if new.id <> old.id
     or new.challenge_id <> old.challenge_id
     or new.user_id <> old.user_id
     or new.invited_by <> old.invited_by
     or new.invited_at <> old.invited_at then
    raise exception 'Challenge participant identity fields are immutable';
  end if;

  if actor = creator
     and new.state = old.state
     and new.responded_at is not distinct from old.responded_at then
    return new;
  end if;

  if actor = creator
     and old.state = 'invited'
     and new.state = 'withdrawn' then
    new.responded_at := now();
    return new;
  end if;

  if actor = old.user_id
     and old.state = 'invited'
     and new.state in ('accepted','declined') then
    new.responded_at := now();
    return new;
  end if;

  raise exception 'Invalid challenge invitation transition';
end;
$$;

revoke all on function private.guard_challenge_participant()
from public, anon, authenticated;

create or replace function private.challenge_participant_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  challenge_title text;
  inviter_name text;
  participant_name text;
  creator_id uuid;
begin
  select c.title, c.creator_id
    into challenge_title, creator_id
  from public.social_challenges c
  where c.id = new.challenge_id;

  select coalesce(p.display_name, p.username::text, 'A friend')
    into inviter_name
  from public.social_profile_cards p
  where p.user_id = new.invited_by;

  select coalesce(p.display_name, p.username::text, 'An athlete')
    into participant_name
  from public.social_profile_cards p
  where p.user_id = new.user_id;

  if tg_op = 'INSERT' and new.state = 'invited' then
    insert into public.social_inbox_events (
      recipient_id, actor_id, kind, title, message, entity_type, entity_id
    )
    values (
      new.user_id,
      new.invited_by,
      'challenge_invite',
      'New challenge',
      inviter_name || ' challenged you: ' ||
        coalesce(challenge_title, 'ATHLTH Challenge'),
      'challenge',
      new.challenge_id
    );

    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.state = 'invited'
     and new.state = 'accepted' then
    insert into public.social_inbox_events (
      recipient_id, actor_id, kind, title, message, entity_type, entity_id
    )
    values (
      creator_id,
      new.user_id,
      'challenge_accepted',
      'Challenge accepted',
      participant_name || ' accepted ' ||
        coalesce(challenge_title, 'your challenge') || '.',
      'challenge',
      new.challenge_id
    );

    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.state = 'invited'
     and new.state = 'declined' then
    insert into public.social_inbox_events (
      recipient_id, actor_id, kind, title, message, entity_type, entity_id
    )
    values (
      creator_id,
      new.user_id,
      'challenge_declined',
      'Challenge declined',
      participant_name || ' declined ' ||
        coalesce(challenge_title, 'your challenge') || '.',
      'challenge',
      new.challenge_id
    );

    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.state = 'invited'
     and new.state = 'withdrawn' then
    delete from public.social_inbox_events
    where recipient_id = new.user_id
      and kind = 'challenge_invite'
      and entity_type = 'challenge'
      and entity_id = new.challenge_id;

    insert into public.social_inbox_events (
      recipient_id, actor_id, kind, title, message, entity_type, entity_id
    )
    values (
      new.user_id,
      creator_id,
      'challenge_withdrawn',
      'Challenge invite withdrawn',
      inviter_name || ' withdrew ' ||
        coalesce(challenge_title, 'a challenge invite') || '.',
      'challenge',
      new.challenge_id
    );

    return new;
  end if;

  return new;
end;
$$;

revoke all on function private.challenge_participant_event()
from public, anon, authenticated;

drop trigger if exists social_challenge_participants_event
on public.social_challenge_participants;

create trigger social_challenge_participants_event
after insert or update of state
on public.social_challenge_participants
for each row execute function private.challenge_participant_event();

create or replace function public.withdraw_social_challenge_invite(
  p_participant_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_challenge_id uuid;
  v_state text;
  v_creator_id uuid;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  select
    p.challenge_id,
    p.state,
    c.creator_id
  into
    v_challenge_id,
    v_state,
    v_creator_id
  from public.social_challenge_participants p
  join public.social_challenges c
    on c.id = p.challenge_id
  where p.id = p_participant_id
  for update of p;

  if v_challenge_id is null then
    return;
  end if;

  if v_creator_id <> v_actor then
    raise exception 'Only the challenge creator can withdraw an invite';
  end if;

  if v_state <> 'invited' then
    raise exception 'Only unanswered challenge invites can be withdrawn';
  end if;

  update public.social_challenge_participants
  set state = 'withdrawn',
      responded_at = now()
  where id = p_participant_id;
end;
$$;

revoke all on function public.withdraw_social_challenge_invite(uuid)
from public, anon;

grant execute on function public.withdraw_social_challenge_invite(uuid)
to authenticated;

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
    actor_id,
    kind,
    title,
    message,
    entity_type,
    entity_id
  )
  values (
    new.recipient_id,
    new.sender_id,
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

create or replace function private.respond_to_direct_message_request_impl(
  conversation_id uuid,
  accept_request boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
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
      actor_id,
      kind,
      title,
      message,
      entity_type,
      entity_id
    )
    values (
      c.requested_by,
      actor,
      'message_request_accepted',
      'Message request accepted',
      coalesce(requester_name, 'Someone') ||
        ' accepted your message request.',
      'direct_conversation',
      c.id
    );
  end if;
end;
$$;

revoke all on function private.respond_to_direct_message_request_impl(uuid, boolean)
from public, anon, authenticated;
