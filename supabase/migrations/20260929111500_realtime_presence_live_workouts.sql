-- ATHLTH realtime presence + live workout sharing.
-- Exact live GPS coordinates are never persisted; they are sent only through
-- authorized Supabase Realtime Broadcast channels while a workout is active.

alter table public.profile_social_settings
    add column if not exists share_online_status boolean not null default false,
    add column if not exists share_live_workout_location boolean not null default false,
    add column if not exists live_workout_audience text not null default 'mutuals'
        check (live_workout_audience in ('mutuals', 'followers'));

create table if not exists public.social_online_presence (
    user_id uuid primary key references public.profiles(id) on delete cascade,
    last_seen_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.social_online_presence enable row level security;

revoke all on public.social_online_presence from anon;
revoke all on public.social_online_presence from authenticated;
grant select, insert, update, delete on public.social_online_presence to authenticated;

create or replace function private.can_view_online_presence(
    p_target uuid,
    p_viewer uuid default (select auth.uid())
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select
        p_viewer is not null
        and (
            p_viewer = p_target
            or (
                coalesce(
                    (
                        select s.share_online_status
                        from public.profile_social_settings s
                        where s.user_id = p_target
                    ),
                    false
                )
                and not exists (
                    select 1
                    from public.user_blocks b
                    where
                        (b.blocker_id = p_target and b.blocked_id = p_viewer)
                        or
                        (b.blocker_id = p_viewer and b.blocked_id = p_target)
                )
                and exists (
                    select 1
                    from public.profile_follows f
                    where f.follower_id = p_viewer
                      and f.following_id = p_target
                )
            )
        );
$$;

revoke all on function private.can_view_online_presence(uuid, uuid) from public;
revoke all on function private.can_view_online_presence(uuid, uuid) from anon;
grant execute on function private.can_view_online_presence(uuid, uuid) to authenticated;

drop policy if exists "online_presence_select_allowed"
on public.social_online_presence;
create policy "online_presence_select_allowed"
on public.social_online_presence
for select
to authenticated
using (
    private.can_view_online_presence(
        user_id,
        (select auth.uid())
    )
);

drop policy if exists "online_presence_insert_own"
on public.social_online_presence;
create policy "online_presence_insert_own"
on public.social_online_presence
for insert
to authenticated
with check (
    user_id = (select auth.uid())
);

drop policy if exists "online_presence_update_own"
on public.social_online_presence;
create policy "online_presence_update_own"
on public.social_online_presence
for update
to authenticated
using (
    user_id = (select auth.uid())
)
with check (
    user_id = (select auth.uid())
);

drop policy if exists "online_presence_delete_own"
on public.social_online_presence;
create policy "online_presence_delete_own"
on public.social_online_presence
for delete
to authenticated
using (
    user_id = (select auth.uid())
);

create table if not exists public.live_workout_sessions (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references public.profiles(id) on delete cascade,
    activity text not null,
    title text,
    mode text not null default 'workout'
        check (mode in ('workout', 'ghost')),
    ghost_reference_id uuid,
    visibility text not null default 'mutuals'
        check (visibility in ('mutuals', 'followers')),
    channel_topic text not null unique,
    status text not null default 'active'
        check (status in ('active', 'paused', 'ended')),
    started_at timestamptz not null default now(),
    ended_at timestamptz,
    last_broadcast_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (channel_topic = 'live-workout:' || id::text)
);

create index if not exists live_workout_sessions_owner_status_idx
    on public.live_workout_sessions(owner_id, status, started_at desc);

create index if not exists live_workout_sessions_active_idx
    on public.live_workout_sessions(status, last_broadcast_at desc)
    where status in ('active', 'paused');

create index if not exists live_workout_sessions_ghost_reference_idx
    on public.live_workout_sessions(ghost_reference_id, status)
    where ghost_reference_id is not null;

alter table public.live_workout_sessions enable row level security;

revoke all on public.live_workout_sessions from anon;
revoke all on public.live_workout_sessions from authenticated;
grant select, insert, update, delete on public.live_workout_sessions to authenticated;

create or replace function private.can_view_live_workout(
    p_session uuid,
    p_viewer uuid default (select auth.uid())
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select exists (
        select 1
        from public.live_workout_sessions l
        where l.id = p_session
          and p_viewer is not null
          and (
              l.owner_id = p_viewer
              or (
                  l.status in ('active', 'paused')
                  and coalesce(
                      (
                          select s.share_live_workout_location
                          from public.profile_social_settings s
                          where s.user_id = l.owner_id
                      ),
                      false
                  )
                  and not exists (
                      select 1
                      from public.user_blocks b
                      where
                          (b.blocker_id = l.owner_id and b.blocked_id = p_viewer)
                          or
                          (b.blocker_id = p_viewer and b.blocked_id = l.owner_id)
                  )
                  and (
                      (
                          l.visibility = 'followers'
                          and exists (
                              select 1
                              from public.profile_follows f
                              where f.follower_id = p_viewer
                                and f.following_id = l.owner_id
                          )
                      )
                      or
                      (
                          l.visibility = 'mutuals'
                          and exists (
                              select 1
                              from public.profile_follows f1
                              where f1.follower_id = p_viewer
                                and f1.following_id = l.owner_id
                          )
                          and exists (
                              select 1
                              from public.profile_follows f2
                              where f2.follower_id = l.owner_id
                                and f2.following_id = p_viewer
                          )
                      )
                  )
              )
          )
    );
$$;

revoke all on function private.can_view_live_workout(uuid, uuid) from public;
revoke all on function private.can_view_live_workout(uuid, uuid) from anon;
grant execute on function private.can_view_live_workout(uuid, uuid) to authenticated;

drop policy if exists "live_workouts_select_allowed"
on public.live_workout_sessions;
create policy "live_workouts_select_allowed"
on public.live_workout_sessions
for select
to authenticated
using (
    private.can_view_live_workout(
        id,
        (select auth.uid())
    )
);

drop policy if exists "live_workouts_insert_own"
on public.live_workout_sessions;
create policy "live_workouts_insert_own"
on public.live_workout_sessions
for insert
to authenticated
with check (
    owner_id = (select auth.uid())
    and channel_topic = 'live-workout:' || id::text
);

drop policy if exists "live_workouts_update_own"
on public.live_workout_sessions;
create policy "live_workouts_update_own"
on public.live_workout_sessions
for update
to authenticated
using (
    owner_id = (select auth.uid())
)
with check (
    owner_id = (select auth.uid())
);

drop policy if exists "live_workouts_delete_own"
on public.live_workout_sessions;
create policy "live_workouts_delete_own"
on public.live_workout_sessions
for delete
to authenticated
using (
    owner_id = (select auth.uid())
);

-- Private Realtime Broadcast authorization. The owner may send; only viewers
-- accepted by the live-workout RLS helper may receive.
drop policy if exists "athlth_live_workout_broadcast_read"
on realtime.messages;
create policy "athlth_live_workout_broadcast_read"
on realtime.messages
for select
to authenticated
using (
    realtime.messages.extension = 'broadcast'
    and exists (
        select 1
        from public.live_workout_sessions l
        where l.channel_topic = (select realtime.topic())
          and private.can_view_live_workout(
              l.id,
              (select auth.uid())
          )
    )
);

drop policy if exists "athlth_live_workout_broadcast_write"
on realtime.messages;
create policy "athlth_live_workout_broadcast_write"
on realtime.messages
for insert
to authenticated
with check (
    realtime.messages.extension = 'broadcast'
    and exists (
        select 1
        from public.live_workout_sessions l
        where l.channel_topic = (select realtime.topic())
          and l.owner_id = (select auth.uid())
          and l.status in ('active', 'paused')
    )
);

-- Session start/stop and online heartbeat rows are low frequency and useful to
-- observe through Postgres Changes. GPS itself never enters this publication.
do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'social_online_presence'
    ) then
        alter publication supabase_realtime
            add table public.social_online_presence;
    end if;

    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'live_workout_sessions'
    ) then
        alter publication supabase_realtime
            add table public.live_workout_sessions;
    end if;
end
$$;
