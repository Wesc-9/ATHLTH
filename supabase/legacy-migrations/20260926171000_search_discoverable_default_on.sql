-- Make profile search discoverability opt-out for new users only.
-- Existing rows are intentionally left unchanged so prior user choices remain intact.

alter table public.profile_social_settings
  alter column discoverable set default true;
