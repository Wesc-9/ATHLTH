-- New profiles are public and searchable. Existing choices remain unchanged.
-- Profile sections, workout sharing and route privacy retain their own defaults.
alter table public.profile_social_settings
  alter column profile_visibility set default 'public',
  alter column discoverable set default true;
