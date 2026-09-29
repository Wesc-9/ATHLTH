-- Online presence + privacy-first live Ghost Race locations.
-- Exact live coordinates are ephemeral, never public, and only visible to
-- authenticated followers when the runner explicitly enables sharing.

alter table public.profile_social_settings
  add column if not exists share_online_status boolean not null default false;

comment on column public.profile_social_settings.share_online_status is
  'Whether followers may see the user as online. Defaults off.';

create table if not exists public.user_online_presence_sessions (
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null,
  last_seen_at timestamptz not null default now(),
  primary key (user_id, session_id)
);

create index if not exists user_online_presence_sessions_seen_idx
on public.user_online_presence_sessions(last_seen_at desc);

alter table public.user_online_presence_sessions enable row level security;

revoke all on public.user_online_presence_sessions from anon;
revoke all on public.user_online_presence_sessions from authenticated;
grant select, insert, update, delete
on public.user_online_presence_sessions
to authenticated;

drop policy if exists "online presence select allowed"
on public.user_online_presence_sessions;
create policy "online presence select allowed"
on public.user_online_presence_sessions
for select
to authenticated
using (
  (select auth.uid()) = user_id
  or (
    last_seen_at > now() - interval '2 minutes'
    and exists (
      select 1
      from public.profile_social_settings s
      where s.user_id = user_online_presence_sessions.user_id
        and s.share_online_status = true
    )
    and private.is_following(user_id)
    and not private.is_blocked(user_id)
  )
);

drop policy if exists "online presence insert own"
on public.user_online_presence_sessions;
create policy "online presence insert own"
on public.user_online_presence_sessions
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "online presence update own"
on public.user_online_presence_sessions;
create policy "online presence update own"
on public.user_online_presence_sessions
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "online presence delete own"
on public.user_online_presence_sessions;
create policy "online presence delete own"
on public.user_online_presence_sessions
for delete
to authenticated
using ((select auth.uid()) = user_id);

create table if not exists public.ghost_live_sessions (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  source_reference_id uuid,
  status text not null default 'running'
    check (status in ('running', 'completed', 'cancelled', 'failed')),
  share_location boolean not null default true,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '6 hours')
);

create index if not exists ghost_live_sessions_owner_status_idx
on public.ghost_live_sessions(owner_id, status, updated_at desc);

create index if not exists ghost_live_sessions_reference_idx
on public.ghost_live_sessions(source_reference_id, status, updated_at desc);

alter table public.ghost_live_sessions enable row level security;

revoke all on public.ghost_live_sessions from anon;
revoke all on public.ghost_live_sessions from authenticated;
grant select, insert, update, delete
on public.ghost_live_sessions
to authenticated;

create or replace function private.can_view_ghost_live_session(target_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.ghost_live_sessions s
    where s.id = target_session_id
      and (
        (select auth.uid()) = s.owner_id
        or (
          s.share_location = true
          and s.status = 'running'
          and s.expires_at > now()
          and private.is_following(s.owner_id)
          and not private.is_blocked(s.owner_id)
        )
      )
  );
$$;

revoke all on function private.can_view_ghost_live_session(uuid)
from public, anon, authenticated;

drop policy if exists "ghost live sessions select allowed"
on public.ghost_live_sessions;
create policy "ghost live sessions select allowed"
on public.ghost_live_sessions
for select
to authenticated
using (
  (select auth.uid()) = owner_id
  or (
    share_location = true
    and status = 'running'
    and expires_at > now()
    and private.is_following(owner_id)
    and not private.is_blocked(owner_id)
  )
);

drop policy if exists "ghost live sessions insert own"
on public.ghost_live_sessions;
create policy "ghost live sessions insert own"
on public.ghost_live_sessions
for insert
to authenticated
with check ((select auth.uid()) = owner_id);

drop policy if exists "ghost live sessions update own"
on public.ghost_live_sessions;
create policy "ghost live sessions update own"
on public.ghost_live_sessions
for update
to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

drop policy if exists "ghost live sessions delete own"
on public.ghost_live_sessions;
create policy "ghost live sessions delete own"
on public.ghost_live_sessions
for delete
to authenticated
using ((select auth.uid()) = owner_id);

create table if not exists public.ghost_live_positions (
  session_id uuid primary key
    references public.ghost_live_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  elapsed_seconds double precision not null default 0 check (elapsed_seconds >= 0),
  distance_meters double precision not null default 0 check (distance_meters >= 0),
  heart_rate_bpm double precision,
  updated_at timestamptz not null default now()
);

create index if not exists ghost_live_positions_updated_idx
on public.ghost_live_positions(updated_at desc);

alter table public.ghost_live_positions enable row level security;

revoke all on public.ghost_live_positions from anon;
revoke all on public.ghost_live_positions from authenticated;
grant select, insert, update, delete
on public.ghost_live_positions
to authenticated;

drop policy if exists "ghost live positions select allowed"
on public.ghost_live_positions;
create policy "ghost live positions select allowed"
on public.ghost_live_positions
for select
to authenticated
using (
  updated_at > now() - interval '90 seconds'
  and private.can_view_ghost_live_session(session_id)
);

drop policy if exists "ghost live positions insert own"
on public.ghost_live_positions;
create policy "ghost live positions insert own"
on public.ghost_live_positions
for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and exists (
    select 1
    from public.ghost_live_sessions s
    where s.id = session_id
      and s.owner_id = (select auth.uid())
      and s.status = 'running'
      and s.share_location = true
  )
);

drop policy if exists "ghost live positions update own"
on public.ghost_live_positions;
create policy "ghost live positions update own"
on public.ghost_live_positions
for update
to authenticated
using ((select auth.uid()) = user_id)
with check (
  (select auth.uid()) = user_id
  and exists (
    select 1
    from public.ghost_live_sessions s
    where s.id = session_id
      and s.owner_id = (select auth.uid())
      and s.status = 'running'
      and s.share_location = true
  )
);

drop policy if exists "ghost live positions delete own"
on public.ghost_live_positions;
create policy "ghost live positions delete own"
on public.ghost_live_positions
for delete
to authenticated
using ((select auth.uid()) = user_id);

-- Keep the tables ready for Supabase Realtime without making the iOS client
-- depend on Realtime for correctness. The first implementation has a bounded
-- polling fallback, so reconnects and background transitions remain robust.
do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'user_online_presence_sessions'
    ) then
      execute 'alter publication supabase_realtime add table public.user_online_presence_sessions';
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'ghost_live_sessions'
    ) then
      execute 'alter publication supabase_realtime add table public.ghost_live_sessions';
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'ghost_live_positions'
    ) then
      execute 'alter publication supabase_realtime add table public.ghost_live_positions';
    end if;
  end if;
end
$$;
