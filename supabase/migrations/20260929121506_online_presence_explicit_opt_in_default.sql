-- Make online presence explicit opt-in for existing and future users.
-- The realtime feature was not yet shipped when the original migration was
-- applied, so no production user could have intentionally enabled it yet.

alter table public.profile_social_settings
  alter column show_online_status set default false;

update public.profile_social_settings
set show_online_status = false
where show_online_status = true;

delete from public.social_online_presence;
