alter table public.athlth_tournaments
add column if not exists competition_settings_applied boolean not null default false;