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
