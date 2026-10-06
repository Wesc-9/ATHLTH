-- Train Together: public join policy + physical/remote social workout modes.
-- Keeps existing listings backwards compatible: physical + request-to-join remain defaults.

alter table public.train_together_posts
  add column if not exists participation_mode text not null default 'physical',
  add column if not exists join_policy text not null default 'request';

alter table public.train_together_posts
  drop constraint if exists train_together_posts_participation_mode_check;
alter table public.train_together_posts
  add constraint train_together_posts_participation_mode_check
  check (participation_mode in ('physical','remote'));

alter table public.train_together_posts
  drop constraint if exists train_together_posts_join_policy_check;
alter table public.train_together_posts
  add constraint train_together_posts_join_policy_check
  check (join_policy in ('request','open'));

create or replace function public.join_train_together_open(
  p_post_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  post_row public.train_together_posts%rowtype;
  existing_request public.train_together_requests%rowtype;
  session_id uuid;
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
     or post_row.creator_id = actor
     or post_row.join_policy <> 'open'
     or post_row.status <> 'open'
     or post_row.scheduled_start <= now()
     or post_row.accepted_guests >= post_row.max_guests then
    raise exception 'This Train Together workout is not available';
  end if;

  if private.is_blocked(post_row.creator_id) then
    raise exception 'This Train Together workout is not available';
  end if;

  select * into existing_request
  from public.train_together_requests
  where post_id = post_row.id
    and requester_id = actor
  for update;

  if existing_request.id is not null
     and existing_request.state = 'accepted' then
    return post_row.social_workout_session_id;
  end if;

  select
    coalesce(nullif(btrim(display_name), ''), nullif(btrim(username::text), ''), 'ATHLTH Athlete'),
    username::text,
    avatar_url
  into display_name, username_value, avatar_value
  from public.social_profile_cards
  where user_id = actor;

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
    null,
    'accepted',
    now(),
    now(),
    now()
  )
  on conflict (post_id, requester_id)
  do update set
    requester_display_name = excluded.requester_display_name,
    requester_username = excluded.requester_username,
    requester_avatar_url = excluded.requester_avatar_url,
    message = null,
    state = 'accepted',
    responded_at = now(),
    updated_at = now()
  returning id into request_id;

  session_id := post_row.social_workout_session_id;

  if session_id is null then
    session_id := gen_random_uuid();

    insert into public.social_workout_sessions (
      id,
      creator_id,
      title,
      workout_kind,
      status,
      started_at,
      ended_at,
      source_workout_id,
      created_at,
      updated_at,
      invite_payload,
      coordinated_start_at
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
      id,
      session_id,
      user_id,
      invited_by,
      state,
      display_name_snapshot,
      username_snapshot,
      invited_at,
      responded_at
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
    set
      social_workout_session_id = session_id,
      updated_at = now()
    where id = post_row.id;
  end if;

  insert into public.social_workout_participants (
    id,
    session_id,
    user_id,
    invited_by,
    state,
    display_name_snapshot,
    username_snapshot,
    invited_at,
    responded_at
  )
  values (
    gen_random_uuid(),
    session_id,
    actor,
    post_row.creator_id,
    'accepted',
    left(display_name, 100),
    nullif(left(coalesce(username_value, ''), 100), ''),
    now(),
    now()
  )
  on conflict (session_id, user_id)
  do update set
    state = 'accepted',
    responded_at = now();

  update public.train_together_posts
  set
    accepted_guests = accepted_guests + 1,
    status = case
      when accepted_guests + 1 >= max_guests then 'full'
      else 'open'
    end,
    updated_at = now()
  where id = post_row.id;

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
    'train_together_request_accepted',
    'New Train Together participant',
    display_name || ' joined ' || post_row.title || '.',
    'workout_session',
    session_id
  );

  return session_id;
end;
$$;

revoke all on function public.join_train_together_open(uuid)
from public, anon;
grant execute on function public.join_train_together_open(uuid)
to authenticated;
