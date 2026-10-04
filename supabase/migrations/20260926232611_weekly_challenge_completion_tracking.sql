alter table public.official_weekly_challenge_participants
  add column if not exists completed_at timestamptz,
  add column if not exists completion_value double precision;

drop policy if exists official_weekly_participants_update_self
  on public.official_weekly_challenge_participants;

create policy official_weekly_participants_update_self
  on public.official_weekly_challenge_participants
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create index if not exists official_weekly_participants_completed_idx
  on public.official_weekly_challenge_participants(challenge_id, completed_at)
  where completed_at is not null;
