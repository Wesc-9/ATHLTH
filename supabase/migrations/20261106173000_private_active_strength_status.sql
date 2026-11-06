-- Owner-only, short-lived strength progress summary for read-only iPad Studio.
-- Contains no GPS track, heart-rate samples or HealthKit records.
-- The client must opt in before publishing; expiry prevents a stale workout
-- from appearing to be live when an iPhone disconnects.
create table if not exists public.private_active_strength_status (
  user_id uuid primary key references auth.users(id) on delete cascade,
  snapshot jsonb not null check (
    jsonb_typeof(snapshot) = 'object'
    and octet_length(snapshot::text) <= 32768
  ),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '2 minutes')
);

create index if not exists private_active_strength_status_expiry_idx
  on public.private_active_strength_status (expires_at);

alter table public.private_active_strength_status enable row level security;

revoke all on public.private_active_strength_status from public, anon;
grant select, insert, update, delete on public.private_active_strength_status
  to authenticated;

drop policy if exists "Owner can read active strength status"
  on public.private_active_strength_status;
create policy "Owner can read active strength status"
  on public.private_active_strength_status
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Owner can publish active strength status"
  on public.private_active_strength_status;
create policy "Owner can publish active strength status"
  on public.private_active_strength_status
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Owner can refresh active strength status"
  on public.private_active_strength_status;
create policy "Owner can refresh active strength status"
  on public.private_active_strength_status
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Owner can delete active strength status"
  on public.private_active_strength_status;
create policy "Owner can delete active strength status"
  on public.private_active_strength_status
  for delete to authenticated
  using ((select auth.uid()) = user_id);
