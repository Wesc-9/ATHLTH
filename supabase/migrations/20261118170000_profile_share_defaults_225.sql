-- ATHLTH 2.2.5: new account profile defaults only.
-- Never UPDATE existing profiles or retroactively widen earlier consent.
-- When enabled, these two sections are limited to friends unless the
-- athlete explicitly changes their audience through a separate control.
alter table public.profile_social_settings
    alter column share_performance_stats set default true,
    alter column performance_stats_visibility set default 'friends',
    alter column share_gear set default true,
    alter column gear_visibility set default 'friends';

-- Other sharing columns keep their established privacy-first defaults.
