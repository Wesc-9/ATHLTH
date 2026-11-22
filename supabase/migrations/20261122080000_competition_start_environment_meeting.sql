alter table public.athlth_tournaments
 add column if not exists start_mode text not null default 'manual',
 add column if not exists required_environment text not null default 'any',
 add column if not exists meeting_place text,
 add column if not exists meeting_lat double precision,
 add column if not exists meeting_lon double precision;
alter table public.athlth_tournaments
 drop constraint if exists athlth_competition_start_mode_check,
 add constraint athlth_competition_start_mode_check check(start_mode in ('manual','when_ready','scheduled')),
 drop constraint if exists athlth_competition_environment_check,
 add constraint athlth_competition_environment_check check(required_environment in ('any','outdoor','gym')),
 drop constraint if exists athlth_competition_meeting_coordinates_check,
 add constraint athlth_competition_meeting_coordinates_check check(
 (meeting_lat is null and meeting_lon is null) or
 (meeting_lat between -90 and 90 and meeting_lon between -180 and 180)
 ),
 drop constraint if exists athlth_competition_meeting_place_check,
 add constraint athlth_competition_meeting_place_check check(length(coalesce(meeting_place,'')) <= 240);