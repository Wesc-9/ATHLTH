-- Allow verified open guest registration without broad INSERT permissions; repair request-based joining.
-- Functions are replayable: CREATE OR REPLACE preserves configured grants.
-- private.guard_social_workout_participant
CREATE OR REPLACE FUNCTION private.guard_social_workout_participant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  actor uuid := (select auth.uid());
  creator uuid;
  scheduled_start timestamptz;
  marketplace_accept boolean := false;
begin
  select s.creator_id, s.coordinated_start_at
    into creator, scheduled_start
  from public.social_workout_sessions s
  where s.id = coalesce(new.session_id, old.session_id);

  if creator is null then
    raise exception 'Workout session not found';
  end if;

  if tg_op = 'INSERT' then
    if actor <> creator or new.invited_by <> actor then
      -- A signed-in guest may add only themselves and the creator as part of
      -- an already-authorized open Train Together registration. The RPC
      -- creates the accepted request and links the session before inserting.
      -- Unrelated invitations still require the session creator.
      select exists (
        select 1
        from public.train_together_posts p
        join public.train_together_requests r on r.post_id = p.id
        where p.social_workout_session_id = new.session_id
          and p.creator_id = creator
          and p.join_policy = 'open'
          and p.status = 'open'
          and p.scheduled_start > now()
          and r.requester_id = actor
          and r.state = 'accepted'
          and not private.is_blocked(creator)
      ) into marketplace_accept;

      if not coalesce(marketplace_accept, false)
         or new.invited_by is distinct from creator
         or not (
           (new.user_id = creator and new.state = 'creator') or
           (new.user_id = actor and new.state = 'accepted')
         ) then
        raise exception 'Only the workout creator can add participants';
      end if;

      if new.user_id = actor then
        new.responded_at := coalesce(new.responded_at, now());
      end if;
      return new;
    end if;

    if new.user_id = creator then
      if new.state <> 'creator' then
        raise exception 'Workout creator must use creator state';
      end if;
      return new;
    end if;

    select exists (
      select 1
      from public.train_together_posts p
      join public.train_together_requests r
        on r.post_id = p.id
      where p.social_workout_session_id = new.session_id
        and p.creator_id = creator
        and r.requester_id = new.user_id
        and r.state = 'accepted'
    ) into marketplace_accept;

    if marketplace_accept and new.state = 'accepted' then
      new.responded_at := coalesce(new.responded_at, now());
      return new;
    end if;

    if new.state <> 'invited' then
      raise exception 'New workout participants must start as invited';
    end if;

    if not private.are_friends(new.user_id) then
      raise exception 'Workout participants must already be friends';
    end if;

    if private.is_blocked(new.user_id) then
      raise exception 'Workout invitation is not available for this user';
    end if;

    return new;
  end if;

  if new.id <> old.id
     or new.session_id <> old.session_id
     or new.user_id <> old.user_id
     or new.invited_by <> old.invited_by
     or new.invited_at <> old.invited_at
     or new.display_name_snapshot <> old.display_name_snapshot
     or new.username_snapshot is distinct from old.username_snapshot then
    raise exception 'Workout participant identity fields are immutable';
  end if;

  if actor = creator and actor <> old.user_id then
    if old.state in ('invited','accepted')
       and new.state = 'declined'
       and old.workout_started_at is null
       and old.launch_failed_at is null
       and new.ready_at is not distinct from old.ready_at
       and new.capture_device is not distinct from old.capture_device
       and new.workout_started_at is not distinct from old.workout_started_at
       and new.workout_finished_at is not distinct from old.workout_finished_at
       and new.launch_failed_at is not distinct from old.launch_failed_at then
      new.responded_at := now();
      return new;
    end if;
    raise exception 'Creator can only withdraw participants before they start';
  end if;

  if actor <> old.user_id then
    raise exception 'Participants can only update their own workout state';
  end if;

  if new.state <> old.state then
    if old.state = 'invited'
       and new.state in ('accepted','declined') then
      if new.ready_at is distinct from old.ready_at
         or new.capture_device is distinct from old.capture_device
         or new.workout_started_at is distinct from old.workout_started_at
         or new.workout_finished_at is distinct from old.workout_finished_at
         or new.launch_failed_at is distinct from old.launch_failed_at then
        raise exception 'Accept or decline the invitation before changing workout readiness';
      end if;
      new.responded_at := now();
      return new;
    end if;

    if old.state = 'accepted'
       and new.state = 'declined'
       and old.workout_started_at is null
       and old.launch_failed_at is null then
      new.responded_at := now();
      return new;
    end if;

    raise exception 'Invalid workout invitation transition';
  end if;

  if old.state not in ('creator','accepted') then
    raise exception 'Only accepted participants can update workout readiness';
  end if;

  if new.responded_at is distinct from old.responded_at then
    raise exception 'Workout response timestamp is immutable';
  end if;

  if new.ready_at is not null and new.capture_device is null then
    raise exception 'A ready participant must choose a workout device';
  end if;

  if old.workout_started_at is not null
     and new.capture_device is distinct from old.capture_device then
    raise exception 'Workout device cannot change after the workout starts';
  end if;

  if new.workout_started_at is not null then
    if new.ready_at is null then
      raise exception 'Participant must be ready before starting';
    end if;
    if scheduled_start is null then
      raise exception 'Shared workout has not been started by the creator';
    end if;
    if new.launch_failed_at is not null then
      raise exception 'A failed launch cannot also be marked started';
    end if;
  end if;

  if new.launch_failed_at is not null then
    if new.ready_at is null then
      raise exception 'Participant must be ready before a launch can fail';
    end if;
    if new.workout_started_at is not null then
      raise exception 'A started workout cannot be marked as launch failed';
    end if;
  end if;

  if new.workout_finished_at is not null
     and new.workout_started_at is null then
    raise exception 'Workout cannot finish before it starts';
  end if;

  return new;
end;
$function$;

-- public.request_train_together_join
CREATE OR REPLACE FUNCTION public.request_train_together_join(p_post_id uuid, p_message text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  actor uuid := (select auth.uid());
  post_row public.train_together_posts%rowtype;
  request_id uuid;
  display_name text;
  username_value text;
  avatar_value text;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  select * into post_row
  from public.train_together_posts
  where id = p_post_id
  for update;

  if post_row.id is null
     or post_row.status <> 'open'
     or post_row.scheduled_start <= now()
     or post_row.creator_id = actor
     or post_row.accepted_guests >= post_row.max_guests then
    raise exception 'This Train Together workout is not available';
  end if;

  if private.is_blocked(post_row.creator_id) then
    raise exception 'This Train Together workout is not available';
  end if;

  -- Explicit profile alias prevents a PL/pgSQL column/variable collision.
  select
    coalesce(nullif(btrim(p.display_name), ''), nullif(btrim(p.username::text), ''), 'ATHLTH Athlete'),
    p.username::text,
    p.avatar_url
  into display_name, username_value, avatar_value
  from public.social_profile_cards as p
  where p.user_id = actor;

  display_name := coalesce(display_name, 'ATHLTH Athlete');

  insert into public.train_together_requests (
    post_id,
    requester_id,
    requester_display_name,
    requester_username,
    requester_avatar_url,
    message,
    state,
    created_at,
    responded_at,
    updated_at
  )
  values (
    post_row.id,
    actor,
    left(display_name, 100),
    nullif(left(coalesce(username_value, ''), 100), ''),
    nullif(left(coalesce(avatar_value, ''), 2000), ''),
    nullif(left(btrim(coalesce(p_message, '')), 500), ''),
    'pending',
    now(),
    null,
    now()
  )
  on conflict (post_id, requester_id)
  do update set
    requester_display_name = excluded.requester_display_name,
    requester_username = excluded.requester_username,
    requester_avatar_url = excluded.requester_avatar_url,
    message = excluded.message,
    state = 'pending',
    created_at = now(),
    responded_at = null,
    updated_at = now()
  returning id into request_id;

  insert into public.social_inbox_events (
    recipient_id,
    actor_id,
    kind,
    title,
    message,
    entity_type,
    entity_id
  )
  values (
    post_row.creator_id,
    actor,
    'train_together_request',
    'Train Together request',
    display_name || ' wants to join ' || post_row.title || '.',
    'train_together_request',
    request_id
  );

  return request_id;
end;
$function$;
