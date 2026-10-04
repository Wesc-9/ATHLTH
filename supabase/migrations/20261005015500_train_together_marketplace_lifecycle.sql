-- Harden Train Together marketplace lifecycle:
-- hide blocked users, reopen spots when accepted participants leave,
-- mirror session completion/cancellation and notify accepted guests.

drop policy if exists train_together_posts_read
on public.train_together_posts;

create policy train_together_posts_read
on public.train_together_posts for select
to authenticated
using (
  creator_id = (select auth.uid())
  or (
    status in ('open','full')
    and scheduled_start > now() - interval '2 hours'
    and not private.is_blocked(creator_id)
  )
  or exists (
    select 1
    from public.train_together_requests r
    where r.post_id = id
      and r.requester_id = (select auth.uid())
  )
);

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
      'train_together_cancelled',
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

create or replace function private.sync_train_together_participant_state()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  post_id_value uuid;
  actor uuid := (select auth.uid());
begin
  if old.state = 'accepted'
     and new.state = 'declined' then
    select p.id
      into post_id_value
    from public.train_together_posts p
    where p.social_workout_session_id = new.session_id
    limit 1;

    if post_id_value is not null then
      update public.train_together_posts p
      set
        accepted_guests = greatest(p.accepted_guests - 1, 0),
        status = case
          when p.status in ('cancelled','completed') then p.status
          when p.scheduled_start <= now() then p.status
          else 'open'
        end,
        updated_at = now()
      where p.id = post_id_value;

      update public.train_together_requests r
      set
        state = case
          when actor = r.requester_id then 'withdrawn'
          else 'declined'
        end,
        responded_at = now(),
        updated_at = now()
      where r.post_id = post_id_value
        and r.requester_id = new.user_id
        and r.state = 'accepted';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.sync_train_together_participant_state()
from public, anon, authenticated;

drop trigger if exists social_workout_participants_train_together_sync
on public.social_workout_participants;

create trigger social_workout_participants_train_together_sync
after update of state on public.social_workout_participants
for each row
execute function private.sync_train_together_participant_state();

create or replace function private.sync_train_together_session_status()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.status is distinct from old.status
     and new.status in ('completed','cancelled') then
    update public.train_together_posts
    set
      status = new.status,
      updated_at = now()
    where social_workout_session_id = new.id
      and status not in ('completed','cancelled');
  end if;

  return new;
end;
$$;

revoke all on function private.sync_train_together_session_status()
from public, anon, authenticated;

drop trigger if exists social_workout_sessions_train_together_sync
on public.social_workout_sessions;

create trigger social_workout_sessions_train_together_sync
after update of status on public.social_workout_sessions
for each row
execute function private.sync_train_together_session_status();

create or replace function public.cancel_train_together_post(
  p_post_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  post_row public.train_together_posts%rowtype;
begin
  select * into post_row
  from public.train_together_posts
  where id = p_post_id
  for update;

  if post_row.id is null
     or post_row.creator_id <> (select auth.uid())
     or post_row.status not in ('open','full') then
    raise exception 'Train Together workout is not available';
  end if;

  update public.train_together_posts
  set status='cancelled', updated_at=now()
  where id=p_post_id;

  if post_row.social_workout_session_id is not null then
    update public.social_workout_sessions
    set
      status='cancelled',
      ended_at=coalesce(ended_at, now()),
      updated_at=now()
    where id=post_row.social_workout_session_id
      and creator_id=(select auth.uid())
      and status='active';
  end if;

  insert into public.social_inbox_events (
    recipient_id,
    actor_id,
    kind,
    title,
    message,
    entity_type,
    entity_id
  )
  select
    r.requester_id,
    post_row.creator_id,
    'train_together_cancelled',
    'Train Together cancelled',
    post_row.creator_display_name || ' cancelled ' || post_row.title || '.',
    'train_together_post',
    post_row.id
  from public.train_together_requests r
  where r.post_id = post_row.id
    and r.state = 'accepted';
end;
$$;

revoke all on function public.cancel_train_together_post(uuid)
from public, anon;

grant execute on function public.cancel_train_together_post(uuid)
to authenticated;
