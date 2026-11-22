create table if not exists public.athlth_competition_coach_limits(
 user_id uuid primary key references auth.users(id) on delete cascade,
 last_requested_at timestamptz not null default now()
);
alter table public.athlth_competition_coach_limits enable row level security;
revoke all on public.athlth_competition_coach_limits from public,anon,authenticated;