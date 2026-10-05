-- Social workout companion layer: live progress and workout-scoped chat.

create table if not exists public.social_workout_live_states (
  session_id uuid not null references public.social_workout_sessions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  display_name_snapshot text not null check (char_length(btrim(display_name_snapshot)) between 1 and 100),
  workout_kind text not null check (char_length(workout_kind) between 1 and 40),
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (session_id, user_id)
);

create index if not exists social_workout_live_states_session_idx
  on public.social_workout_live_states(session_id, updated_at desc);

create table if not exists public.social_workout_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.social_workout_sessions(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  sender_display_name text not null check (char_length(btrim(sender_display_name)) between 1 and 100),
  kind text not null default 'text'
    check (kind in ('text','reaction','system')),
  body text check (body is null or char_length(body) <= 800),
  created_at timestamptz not null default now()
);

create index if not exists social_workout_messages_session_idx
  on public.social_workout_messages(session_id, created_at desc);

alter table public.social_workout_live_states enable row level security;
alter table public.social_workout_messages enable row level security;

grant select, insert, update, delete on public.social_workout_live_states to authenticated;
grant select, insert, update, delete on public.social_workout_messages to authenticated;

create or replace function private.is_social_workout_participant(
  p_session_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.social_workout_participants p
    where p.session_id = p_session_id
      and p.user_id = p_user_id
      and p.state in ('creator','accepted')
  );
$$;

revoke all on function private.is_social_workout_participant(uuid, uuid)
from public, anon, authenticated;

create policy social_workout_live_states_read
on public.social_workout_live_states for select
to authenticated
using (
  private.is_social_workout_participant(session_id, (select auth.uid()))
);

create policy social_workout_live_states_write
on public.social_workout_live_states for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and private.is_social_workout_participant(session_id, (select auth.uid()))
);

create policy social_workout_live_states_update
on public.social_workout_live_states for update
to authenticated
using (user_id = (select auth.uid()))
with check (
  user_id = (select auth.uid())
  and private.is_social_workout_participant(session_id, (select auth.uid()))
);

create policy social_workout_messages_read
on public.social_workout_messages for select
to authenticated
using (
  private.is_social_workout_participant(session_id, (select auth.uid()))
);

create policy social_workout_messages_insert
on public.social_workout_messages for insert
to authenticated
with check (
  sender_id = (select auth.uid())
  and private.is_social_workout_participant(session_id, (select auth.uid()))
);
