create table if not exists public.social_workout_sessions (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  workout_kind text not null check (workout_kind in ('running','walking','strength','custom')),
  status text not null default 'active' check (status in ('active','completed','cancelled')),
  started_at timestamptz not null,
  ended_at timestamptz,
  source_workout_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ended_at is null or ended_at >= started_at)
);

create index if not exists social_workout_sessions_creator_idx
  on public.social_workout_sessions(creator_id, created_at desc);

create index if not exists social_workout_sessions_source_idx
  on public.social_workout_sessions(source_workout_id)
  where source_workout_id is not null;

create table if not exists public.social_workout_participants (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.social_workout_sessions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  invited_by uuid not null references public.profiles(id) on delete cascade,
  state text not null check (state in ('creator','invited','accepted','declined')),
  display_name_snapshot text not null,
  username_snapshot text,
  invited_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (session_id, user_id)
);

create index if not exists social_workout_participants_user_idx
  on public.social_workout_participants(user_id, state, invited_at desc);

create index if not exists social_workout_participants_invited_by_idx
  on public.social_workout_participants(invited_by);

alter table public.social_activities
  add column if not exists workout_session_id uuid
  references public.social_workout_sessions(id) on delete set null;

create index if not exists social_activities_workout_session_idx
  on public.social_activities(workout_session_id)
  where workout_session_id is not null;

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
      'workout_invite_accepted'
    )
  );

alter table public.social_workout_sessions enable row level security;
alter table public.social_workout_participants enable row level security;

revoke all on table public.social_workout_sessions from anon, authenticated;
revoke all on table public.social_workout_participants from anon, authenticated;

grant select, insert, update on public.social_workout_sessions to authenticated;
grant select, insert, update on public.social_workout_participants to authenticated;

create or replace function private.is_social_workout_member(session_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
    select 1
    from public.social_workout_sessions s
    where s.id = session_uuid
      and s.creator_id = (select auth.uid())
  )
  or exists (
    select 1
    from public.social_workout_participants p
    where p.session_id = session_uuid
      and p.user_id = (select auth.uid())
      and p.state in ('creator','invited','accepted')
  );
$$;

revoke all on function private.is_social_workout_member(uuid) from public, anon;
grant execute on function private.is_social_workout_member(uuid) to authenticated;

drop policy if exists social_workout_sessions_select_member on public.social_workout_sessions;
create policy social_workout_sessions_select_member
on public.social_workout_sessions for select
to authenticated
using (private.is_social_workout_member(id));

drop policy if exists social_workout_sessions_insert_creator on public.social_workout_sessions;
create policy social_workout_sessions_insert_creator
on public.social_workout_sessions for insert
to authenticated
with check ((select auth.uid()) = creator_id);

drop policy if exists social_workout_sessions_update_creator on public.social_workout_sessions;
create policy social_workout_sessions_update_creator
on public.social_workout_sessions for update
to authenticated
using ((select auth.uid()) = creator_id)
with check ((select auth.uid()) = creator_id);

drop policy if exists social_workout_participants_select_member on public.social_workout_participants;
create policy social_workout_participants_select_member
on public.social_workout_participants for select
to authenticated
using (private.is_social_workout_member(session_id));

drop policy if exists social_workout_participants_insert_creator on public.social_workout_participants;
create policy social_workout_participants_insert_creator
on public.social_workout_participants for insert
to authenticated
with check (
  exists (
    select 1
    from public.social_workout_sessions s
    where s.id = session_id
      and s.creator_id = (select auth.uid())
  )
);

drop policy if exists social_workout_participants_update_self on public.social_workout_participants;
create policy social_workout_participants_update_self
on public.social_workout_participants for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create or replace function private.guard_social_workout_participant()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  creator uuid;
begin
  select s.creator_id into creator
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

  if actor <> old.user_id
     or old.state <> 'invited'
     or new.state not in ('accepted','declined') then
    raise exception 'Invalid workout invitation transition';
  end if;

  new.responded_at := now();
  return new;
end;
$$;

revoke all on function private.guard_social_workout_participant()
from public, anon, authenticated;

drop trigger if exists social_workout_participants_guard
on public.social_workout_participants;

create trigger social_workout_participants_guard
before insert or update on public.social_workout_participants
for each row execute function private.guard_social_workout_participant();

create or replace function private.social_workout_invite_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  workout_title text;
  inviter_name text;
begin
  if tg_op = 'INSERT' and new.state = 'invited' then
    select s.title into workout_title
    from public.social_workout_sessions s
    where s.id = new.session_id;

    select coalesce(p.display_name, p.username::text, 'A friend')
      into inviter_name
    from public.social_profile_cards p
    where p.user_id = new.invited_by;

    insert into public.social_inbox_events (
      recipient_id, kind, title, message, entity_type, entity_id
    )
    values (
      new.user_id,
      'workout_invite',
      'Train together',
      inviter_name || ' invited you to train together: ' || coalesce(workout_title, 'Workout') || '.',
      'workout_session',
      new.session_id
    );

    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.state = 'invited'
     and new.state = 'accepted' then

    select s.title into workout_title
    from public.social_workout_sessions s
    where s.id = new.session_id;

    insert into public.social_inbox_events (
      recipient_id, kind, title, message, entity_type, entity_id
    )
    values (
      new.invited_by,
      'workout_invite_accepted',
      'Training partner joined',
      new.display_name_snapshot || ' accepted your invite for ' || coalesce(workout_title, 'Workout') || '.',
      'workout_session',
      new.session_id
    );
  end if;

  return new;
end;
$$;

revoke all on function private.social_workout_invite_event()
from public, anon, authenticated;

drop trigger if exists social_workout_participants_event
on public.social_workout_participants;

create trigger social_workout_participants_event
after insert or update of state on public.social_workout_participants
for each row execute function private.social_workout_invite_event();

drop trigger if exists social_workout_sessions_updated_at
on public.social_workout_sessions;

create trigger social_workout_sessions_updated_at
before update on public.social_workout_sessions
for each row execute function public.set_updated_at();

drop policy if exists social_activities_insert_own on public.social_activities;
create policy social_activities_insert_own
on public.social_activities for insert
to authenticated
with check (
  (select auth.uid()) = actor_id
  and (
    workout_session_id is null
    or exists (
      select 1
      from public.social_workout_sessions s
      where s.id = workout_session_id
        and s.creator_id = (select auth.uid())
    )
  )
);
