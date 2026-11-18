-- ATHLTH 2.2.5: future users only, with Health-derived data
-- still private by default. No update of existing privacy preferences.
-- Gear identities can be visible to friends on new accounts; the owner
-- may turn this off in Edit Profile > Sharing & privacy.
alter table public.profile_social_settings
    alter column share_gear set default true,
    alter column gear_visibility set default 'friends';
