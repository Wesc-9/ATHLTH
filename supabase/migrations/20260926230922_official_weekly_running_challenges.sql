create or replace function private.is_app_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.account_roles ar
    where ar.user_id = (select auth.uid())
      and ar.role in ('admin', 'owner')
  );
$$;

revoke all on function private.is_app_admin() from public;
grant execute on function private.is_app_admin() to authenticated;

create table if not exists public.official_weekly_challenges (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 120),
  subtitle text not null default '' check (char_length(subtitle) <= 240),
  kind text not null check (kind in ('distance', 'sessions', 'minutes', 'streak')),
  target_value double precision not null check (target_value > 0),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  hero_asset text not null default 'CommunityHero',
  source text not null default 'manual' check (source in ('manual', 'ai')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index if not exists official_weekly_challenges_starts_at_idx
  on public.official_weekly_challenges(starts_at);

create table if not exists public.official_weekly_challenge_participants (
  challenge_id uuid not null references public.official_weekly_challenges(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (challenge_id, user_id)
);

alter table public.official_weekly_challenges enable row level security;
alter table public.official_weekly_challenge_participants enable row level security;

drop policy if exists official_weekly_challenges_select_authenticated
  on public.official_weekly_challenges;
create policy official_weekly_challenges_select_authenticated
  on public.official_weekly_challenges
  for select
  to authenticated
  using (true);

drop policy if exists official_weekly_challenges_admin_insert
  on public.official_weekly_challenges;
create policy official_weekly_challenges_admin_insert
  on public.official_weekly_challenges
  for insert
  to authenticated
  with check (
    private.is_app_admin()
    and created_by = (select auth.uid())
  );

drop policy if exists official_weekly_challenges_admin_update
  on public.official_weekly_challenges;
create policy official_weekly_challenges_admin_update
  on public.official_weekly_challenges
  for update
  to authenticated
  using (private.is_app_admin())
  with check (private.is_app_admin());

drop policy if exists official_weekly_challenges_admin_delete
  on public.official_weekly_challenges;
create policy official_weekly_challenges_admin_delete
  on public.official_weekly_challenges
  for delete
  to authenticated
  using (private.is_app_admin());

drop policy if exists official_weekly_participants_select_authenticated
  on public.official_weekly_challenge_participants;
create policy official_weekly_participants_select_authenticated
  on public.official_weekly_challenge_participants
  for select
  to authenticated
  using (true);

drop policy if exists official_weekly_participants_insert_self
  on public.official_weekly_challenge_participants;
create policy official_weekly_participants_insert_self
  on public.official_weekly_challenge_participants
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists official_weekly_participants_delete_self_or_admin
  on public.official_weekly_challenge_participants;
create policy official_weekly_participants_delete_self_or_admin
  on public.official_weekly_challenge_participants
  for delete
  to authenticated
  using (
    user_id = (select auth.uid())
    or private.is_app_admin()
  );

create or replace function public.shift_official_weekly_challenges_forward(
  p_after timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_app_admin() then
    raise exception 'Admin access required';
  end if;

  update public.official_weekly_challenges
  set starts_at = starts_at - interval '7 days',
      ends_at = ends_at - interval '7 days',
      updated_at = now()
  where starts_at > p_after;
end;
$$;

revoke all on function public.shift_official_weekly_challenges_forward(timestamptz) from public;
grant execute on function public.shift_official_weekly_challenges_forward(timestamptz) to authenticated;
