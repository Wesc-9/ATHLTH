-- Reserve HomeHero for the Home screen only.
update public.profiles set header_artwork_name = 'ProfileHero' where header_artwork_name = 'HomeHero';
update public.community_events set cover_artwork_name = 'CommunityHero' where cover_artwork_name = 'HomeHero';
alter table public.profiles add constraint athlth_profiles_no_home_hero check (header_artwork_name is distinct from 'HomeHero');
alter table public.community_events add constraint athlth_events_no_home_hero check (cover_artwork_name is distinct from 'HomeHero');
alter table public.official_weekly_challenges add constraint athlth_weekly_no_home_hero check (hero_asset not in ('HomeHero','ProfileHero'));
-- Existing active weekly challenges are deliberately not updated: they are immutable.
