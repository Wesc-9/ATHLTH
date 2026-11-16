-- ATHLTH 2.2.3: Enforce mutual follow for friends-only social data.
-- Applied to ATHLTH Developer Supabase as migration 20261116233205.

CREATE OR REPLACE FUNCTION private.can_view_activity(owner_id uuid, activity_visibility text, activity_kind text, activity_metadata jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  select
    (select auth.uid()) = owner_id
    or (
      (select auth.uid()) is not null
      and not private.is_blocked(owner_id)
      and (
        activity_visibility = 'public'
        or (
          activity_visibility = 'friends'
          and private.are_friends(owner_id)
        )
      )
      and private.can_view_social_section(
        owner_id,
        case
          when activity_kind = 'goal' then 'goals'
          when activity_kind = 'trophy' then 'trophies'
          when activity_kind = 'personal_record'
            and coalesce(activity_metadata->>'pr_type', '') = 'running'
            then 'running_prs'
          when activity_kind = 'personal_record'
            and coalesce(activity_metadata->>'pr_type', '') = 'strength'
            then 'strength_prs'
          else 'activity'
        end
      )
    );
$function$;

CREATE OR REPLACE FUNCTION private.can_view_social_section(owner_id uuid, section_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    (select auth.uid()) = owner_id
    or (
      (select auth.uid()) is not null
      and not private.is_blocked(owner_id)
      and (
        coalesce((
          select case section_name
            when 'presence' then s.training_presence_visibility
            when 'performance' then s.performance_stats_visibility
            when 'trophies' then s.trophy_cabinet_visibility
            when 'activity' then s.recent_activity_visibility
            when 'goals' then s.goals_visibility
            when 'gear' then s.gear_visibility
            when 'running_prs' then s.running_prs_visibility
            when 'strength_prs' then s.strength_prs_visibility
            when 'workout_totals' then s.performance_stats_visibility
            else 'private'
          end
          from public.profile_social_settings s
          where s.user_id = owner_id
        ), 'private') = 'public'
        or (
          coalesce((
            select case section_name
              when 'presence' then s.training_presence_visibility
              when 'performance' then s.performance_stats_visibility
              when 'trophies' then s.trophy_cabinet_visibility
              when 'activity' then s.recent_activity_visibility
              when 'goals' then s.goals_visibility
              when 'gear' then s.gear_visibility
              when 'running_prs' then s.running_prs_visibility
              when 'strength_prs' then s.strength_prs_visibility
              when 'workout_totals' then s.performance_stats_visibility
              else 'private'
            end
            from public.profile_social_settings s
            where s.user_id = owner_id
          ), 'private') = 'friends'
          and private.are_friends(owner_id)
        )
      )
    );
$function$;

-- Existing activity metadata may contain HealthKit measurements.
-- Retain only allowlisted nonclinical summary fields, redacting the rest.
UPDATE public.social_activities AS a
SET metadata = COALESCE(
  (SELECT jsonb_object_agg(e.key, e.value)
   FROM jsonb_each(a.metadata) AS e(key, value)
   WHERE e.key = ANY (ARRAY[
     'workout_id', 'kind', 'source', 'effort', 'caption',
     'duration_seconds', 'distance_meters', 'exercise_count',
     'volume_kg', 'muscle_groups', 'with_names', 'with_count',
     'partner_count_selected', 'route_preview', 'hide_route_start_end'
   ])
  ), '{}'::jsonb
) || jsonb_build_object('share_health_data', 'false')
WHERE a.kind = 'workout';
