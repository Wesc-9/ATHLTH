-- Deleting an ATHLTH user must never be blocked by historical
-- Club Arena season authorship or competition-link audit fields.
-- The season and already approved score history remain intact.
alter table public.arena_club_seasons
  drop constraint if exists arena_club_seasons_created_by_fkey;
alter table public.arena_club_seasons
  alter column created_by drop not null;
alter table public.arena_club_seasons
  add constraint arena_club_seasons_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete set null;

alter table public.arena_club_season_series
  drop constraint if exists arena_club_season_series_linked_by_fkey;
alter table public.arena_club_season_series
  alter column linked_by drop not null;
alter table public.arena_club_season_series
  add constraint arena_club_season_series_linked_by_fkey
  foreign key (linked_by) references auth.users(id) on delete set null;
