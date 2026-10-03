-- Profile sections are visible by default for new settings rows.
-- Existing user choices are intentionally preserved. Training presence, online
-- status, live location and live heart-rate sharing remain opt-in.

alter table public.profile_social_settings
  alter column training_focus_visibility set default 'public',
  alter column performance_stats_visibility set default 'public',
  alter column trophy_cabinet_visibility set default 'public',
  alter column recent_activity_visibility set default 'public',
  alter column goals_visibility set default 'public',
  alter column gear_visibility set default 'public',
  alter column running_prs_visibility set default 'public',
  alter column strength_prs_visibility set default 'public',
  alter column share_performance_stats set default true,
  alter column share_trophy_cabinet set default true,
  alter column share_goals set default true,
  alter column share_gear set default true,
  alter column share_recent_activity set default true,
  alter column share_running_prs set default true,
  alter column share_strength_prs set default true,
  alter column share_workout_totals set default true;
