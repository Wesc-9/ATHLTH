-- Official weekly challenges are community-owned records and must outlive
-- the admin account that originally created them. Account deletion previously
-- failed because created_by used ON DELETE RESTRICT.
alter table public.official_weekly_challenges
  alter column created_by drop not null;

alter table public.official_weekly_challenges
  drop constraint if exists official_weekly_challenges_created_by_fkey;

alter table public.official_weekly_challenges
  add constraint official_weekly_challenges_created_by_fkey
  foreign key (created_by)
  references auth.users(id)
  on delete set null;

comment on column public.official_weekly_challenges.created_by is
  'Admin user that originally created the challenge. Null after that account is deleted.';
