-- Use unambiguous unique-constraint name for creator-approved joins.
-- Functions are replayable: CREATE OR REPLACE preserves configured grants.
-- public.respond_train_together_request
CREATE OR REPLACE FUNCTION public.respond_train_together_request(p_request_id uuid, p_action text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  actor uuid := (select auth.uid());
  request_row public.train_together_requests%rowtype;
  post_row public.train_together_posts%rowtype;
  session_id uuid;
  creator_name text;
  creator_username text;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if p_action not in ('accept','decline') then
    raise exception 'Invalid Train Together response';
  end if;

  select * into request_row
  from public.train_together_requests
  where id = p_request_id
  for update;

  if request_row.id is null or request_row.state <> 'pending' then
    raise exception 'Train Together request is not pending';
  end if;

  select * into post_row
  from public.train_together_posts
  where id = request_row.post_id
  for update;

  if post_row.creator_id <> actor then
    raise exception 'Only the workout creator can respond';
  end if;

  if p_action = 'decline' then
    update public.train_together_requests
    set state='declined', responded_at=now(), updated_at=now()
    where id=request_row.id;

    insert into public.social_inbox_events (
      recipient_id, actor_id, kind, title, message, entity_type, entity_id
    )
    values (
      request_row.requester_id,
      actor,
      'train_together_request_declined',
      'Train Together request declined',
      post_row.creator_display_name || ' declined your request for ' || post_row.title || '.',
      'train_together_post',
      post_row.id
    );

    return null;
  end if;

  if post_row.status <> 'open'
     or post_row.scheduled_start <= now()
     or post_row.accepted_guests >= post_row.max_guests then
    raise exception 'This Train Together workout is full or no longer available';
  end if;

  update public.train_together_requests
  set state='accepted', responded_at=now(), updated_at=now()
  where id=request_row.id;

  session_id := post_row.social_workout_session_id;

  if session_id is null then
    session_id := gen_random_uuid();

    insert into public.social_workout_sessions (
      id, creator_id, title, workout_kind, status, started_at,
      ended_at, source_workout_id, created_at, updated_at,
      invite_payload, coordinated_start_at
    )
    values (
      session_id,
      post_row.creator_id,
      post_row.title,
      post_row.workout_kind,
      'active',
      now(),
      null,
      post_row.source_planned_session_id,
      now(),
      now(),
      post_row.workout_payload,
      null
    );

    insert into public.social_workout_participants (
      id, session_id, user_id, invited_by, state,
      display_name_snapshot, username_snapshot,
      invited_at, responded_at
    )
    values (
      gen_random_uuid(),
      session_id,
      post_row.creator_id,
      post_row.creator_id,
      'creator',
      post_row.creator_display_name,
      post_row.creator_username,
      now(),
      now()
    );

    update public.train_together_posts
    set social_workout_session_id=session_id, updated_at=now()
    where id=post_row.id;
  end if;

  insert into public.social_workout_participants (
    id, session_id, user_id, invited_by, state,
    display_name_snapshot, username_snapshot,
    invited_at, responded_at
  )
  values (
    gen_random_uuid(),
    session_id,
    request_row.requester_id,
    post_row.creator_id,
    'accepted',
    request_row.requester_display_name,
    request_row.requester_username,
    request_row.created_at,
    now()
  )
  on conflict on constraint social_workout_participants_session_id_user_id_key
  do update set
    state='accepted',
    responded_at=now();

  update public.train_together_posts
  set
    accepted_guests = accepted_guests + 1,
    status = case
      when accepted_guests + 1 >= max_guests then 'full'
      else 'open'
    end,
    updated_at = now()
  where id=post_row.id;

  insert into public.social_inbox_events (
    recipient_id, actor_id, kind, title, message, entity_type, entity_id
  )
  values (
    request_row.requester_id,
    actor,
    'train_together_request_accepted',
    'You are in',
    post_row.creator_display_name || ' accepted your request for ' || post_row.title || '.',
    'workout_session',
    session_id
  );

  return session_id;
end;
$function$;
