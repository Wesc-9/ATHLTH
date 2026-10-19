-- Keep the legacy focus scalar for older ATHLTH clients, while storing
-- all independently selected profile training interests for 1.8.5 onward.
alter table public.social_training_focus
  add column if not exists focuses text[] not null default '{}'::text[];

update public.social_training_focus
set focuses = case
  when focus = 'hybrid' then array['running', 'strength']::text[]
  else array[focus]::text[]
end
where cardinality(focuses) = 0;

alter table public.social_training_focus
  drop constraint if exists social_training_focus_multi_valid;

alter table public.social_training_focus
  add constraint social_training_focus_multi_valid
  check (
    cardinality(focuses) <= 9
    and focuses <@ array[
      'running', 'strength', 'walking', 'cycling', 'swimming',
      'functionalFitness', 'generalFitness', 'mobility', 'recovery'
    ]::text[]
  );
