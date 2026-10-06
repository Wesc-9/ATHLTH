-- Train Together marketplace: public workout posts with approval-based join requests.
-- Exact meetup details are kept separate and are only visible to the creator
-- and athletes whose request has been accepted.

create table if not exists public.train_together_posts (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles(id) on delete cascade,
  creator_display_name text not null check (char_length(btrim(creator_display_name)) between 1 and 100),
  creator_username text,
  creator_avatar_url text,
  title text not null check (char_length(btrim(title)) between 1 and 160),
  workout_kind text not null check (workout_kind in ('running','walking','strength','custom')),
  scheduled_start timestamptz not null,
  duration_minutes integer check (duration_minutes is null or duration_minutes between 5 and 720),
  distance_kilometers double precision check (distance_kilometers is null or distance_kilometers > 0),
  level text not null default 'all' check (level in ('all','beginner','intermediate','advanced')),
  broad_area text not null check (char_length(btrim(broad_area)) between 2 and 80),
  note text check (note is null or char_length(note) <= 1200),
  max_guests integer not null default 1 check (max_guests between 1 and 10),
  accepted_guests integer not null default 0 check (accepted_guests between 0 and 10),
  status text not null default 'open' check (status in ('open','full','cancelled','completed')),
  workout_payload jsonb,
  source_planned_session_id uuid,
  social_workout_session_id uuid references public.social_workout_sessions(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (accepted_guests <= max_guests),
  check (scheduled_start > created_at - interval '15 minutes'),
  check (workout_payload is null or octet_length(workout_payload::text) <= 1048576)
);

create index if not exists train_together_posts_discovery_idx
  on public.train_together_posts(status, scheduled_start, workout_kind, lower(broad_area));
create index if not exists train_together_posts_creator_idx
  on public.train_together_posts(creator_id, scheduled_start desc);

create table if not exists public.train_together_post_meetups (
  post_id uuid primary key references public.train_together_posts(id) on delete cascade,
  creator_id uuid not null references public.profiles(id) on delete cascade,
  meeting_name text check (meeting_name is null or char_length(btrim(meeting_name)) <= 160),
  meeting_details text check (meeting_details is null or char_length(meeting_details) <= 600),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.train_together_requests (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.train_together_posts(id) on delete cascade,
  requester_id uuid not null references public.profiles(id) on delete cascade,
  requester_display_name text not null check (char_length(btrim(requester_display_name)) between 1 and 100),
  requester_username text,
  requester_avatar_url text,
  message text check (message is null or char_length(message) <= 500),
  state text not null default 'pending' check (state in ('pending','accepted','declined','withdrawn')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(post_id, requester_id)
);

create index if not exists train_together_requests_post_idx
  on public.train_together_requests(post_id, state, created_at desc);
create index if not exists train_together_requests_requester_idx
  on public.train_together_requests(requester_id, state, created_at desc);

alter table public.train_together_posts enable row level security;
alter table public.train_together_post_meetups enable row level security;
alter table public.train_together_requests enable row level security;

revoke all on public.train_together_posts from anon, authenticated;
revoke all on public.train_together_post_meetups from anon, authenticated;
revoke all on public.train_together_requests from anon, authenticated;

grant select, insert, update, delete on public.train_together_posts to authenticated;
grant select, insert, update, delete on public.train_together_post_meetups to authenticated;
grant select, insert, update, delete on public.train_together_requests to authenticated;

drop policy if exists train_together_posts_read on public.train_together_posts;
create policy train_together_posts_read
on public.train_together_posts for select
to authenticated
using (
  creator_id = (select auth.uid())
  or (
    status in ('open','full')
    and scheduled_start > now() - interval '2 hours'
  )
  or exists (
    select 1
    from public.train_together_requests r
    where r.post_id = id
      and r.requester_id = (select auth.uid())
  )
);

drop policy if exists train_together_posts_insert on public.train_together_posts;
create policy train_together_posts_insert
on public.train_together_posts for insert
to authenticated
with check (creator_id = (select auth.uid()));

drop policy if exists train_together_posts_update on public.train_together_posts;
create policy train_together_posts_update
on public.train_together_posts for update
to authenticated
using (creator_id = (select auth.uid()))
with check (creator_id = (select auth.uid()));

drop policy if exists train_together_posts_delete on public.train_together_posts;
create policy train_together_posts_delete
on public.train_together_posts for delete
to authenticated
using (creator_id = (select auth.uid()));

drop policy if exists train_together_meetups_read on public.train_together_post_meetups;
create policy train_together_meetups_read
on public.train_together_post_meetups for select
to authenticated
using (
  creator_id = (select auth.uid())
  or exists (
    select 1
    from public.train_together_requests r
    where r.post_id = train_together_post_meetups.post_id
      and r.requester_id = (select auth.uid())
      and r.state = 'accepted'
  )
);

drop policy if exists train_together_meetups_insert on public.train_together_post_meetups;
create policy train_together_meetups_insert
on public.train_together_post_meetups for insert
to authenticated
with check (creator_id = (select auth.uid()));

drop policy if exists train_together_meetups_update on public.train_together_post_meetups;
create policy train_together_meetups_update
on public.train_together_post_meetups for update
to authenticated
using (creator_id = (select auth.uid()))
with check (creator_id = (select auth.uid()));

drop policy if exists train_together_meetups_delete on public.train_together_post_meetups;
create policy train_together_meetups_delete
on public.train_together_post_meetups for delete
to authenticated
using (creator_id = (select auth.uid()));

drop policy if exists train_together_requests_read on public.train_together_requests;
create policy train_together_requests_read
on public.train_together_requests for select
to authenticated
using (
  requester_id = (select auth.uid())
  or exists (
    select 1
    from public.train_together_posts p
    where p.id = post_id
      and p.creator_id = (select auth.uid())
  )
);

-- Requests are created and transitioned through RPCs only.
drop policy if exists train_together_requests_insert on public.train_together_requests;
drop policy if exists train_together_requests_update on public.train_together_requests;
drop policy if exists train_together_requests_delete on public.train_together_requests;

drop trigger if exists train_together_posts_updated_at on public.train_together_posts;
create trigger train_together_posts_updated_at
before update on public.train_together_posts
for each row execute function public.set_updated_at();

drop trigger if exists train_together_meetups_updated_at on public.train_together_post_meetups;
create trigger train_together_meetups_updated_at
before update on public.train_together_post_meetups
for each row execute function public.set_updated_at();

drop trigger if exists train_together_requests_updated_at on public.train_together_requests;
create trigger train_together_requests_updated_at
before update on public.train_together_requests
for each row execute function public.set_updated_at();

alter table public.social_inbox_events
  drop constraint if exists social_inbox_events_kind_check;

alter table public.social_inbox_events
  add constraint social_inbox_events_kind_check
  check (
    kind in (
      'friend_request',
      'friend_accepted',
      'follow_request',
      'follow_accepted',
      'challenge_invite',
      'challenge_result',
      'challenge_accepted',
      'challenge_declined',
      'challenge_withdrawn',
      'reaction',
      'workout_invite',
      'workout_invite_accepted',
      'train_together_request',
      'train_together_request_accepted',
      'train_together_request_declined',
      'message',
      'message_request',
      'message_request_accepted',
      'mention',
      'group_message',
      'group_update',
      'group_event',
      'group_challenge',
      'group_invite',
      'group_join_request',
      'group_join_approved'
    )
  );

create or replace function public.request_train_together_join(
  p_post_id uuid,
  p_message text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
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
$$;

revoke all on function public.request_train_together_join(uuid, text)
from public, anon;
grant execute on function public.request_train_together_join(uuid, text)
to authenticated;

create or replace function public.withdraw_train_together_request(
  p_request_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  update public.train_together_requests
  set
    state = 'withdrawn',
    responded_at = now(),
    updated_at = now()
  where id = p_request_id
    and requester_id = (select auth.uid())
    and state = 'pending';

  if not found then
    raise exception 'Train Together request is not available';
  end if;
end;
$$;

revoke all on function public.withdraw_train_together_request(uuid)
from public, anon;
grant execute on function public.withdraw_train_together_request(uuid)
to authenticated;

-- Allow an accepted marketplace request to materialize directly as an
-- accepted participant. The requester already consented by asking to join,
-- so a second acceptance step would be redundant.
create or replace function private.guard_social_workout_participant()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
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
      raise exception 'Only the workout creator can add participants';
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
$$;

revoke all on function private.guard_social_workout_participant()
from public, anon, authenticated;

create or replace function public.respond_train_together_request(
  p_request_id uuid,
  p_action text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
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
  on conflict (session_id, user_id)
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
$$;

revoke all on function public.respond_train_together_request(uuid, text)
from public, anon;
grant execute on function public.respond_train_together_request(uuid, text)
to authenticated;

create or replace function public.cancel_train_together_post(
  p_post_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  update public.train_together_posts
  set status='cancelled', updated_at=now()
  where id=p_post_id
    and creator_id=(select auth.uid())
    and status in ('open','full');

  if not found then
    raise exception 'Train Together workout is not available';
  end if;

  update public.social_workout_sessions
  set status='cancelled', ended_at=coalesce(ended_at, now()), updated_at=now()
  where id=(
    select social_workout_session_id
    from public.train_together_posts
    where id=p_post_id
  )
    and creator_id=(select auth.uid())
    and status='active';
end;
$$;

revoke all on function public.cancel_train_together_post(uuid)
from public, anon;
grant execute on function public.cancel_train_together_post(uuid)
to authenticated;
