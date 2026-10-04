-- Both the section switch and its audience must allow access. The profile
-- audience is an upper bound, including for older app versions.
create or replace function private.can_view_social_section(owner_id uuid, section_name text)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public, private
as $function$
  select (select auth.uid()) = owner_id or (
    (select auth.uid()) is not null
    and not private.is_blocked(owner_id)
    and exists (
      select 1 from public.profile_social_settings s
      where s.user_id = owner_id
        and (s.profile_visibility = 'public'
          or (s.profile_visibility = 'friends' and private.are_friends(owner_id)))
        and case section_name
          when 'training_focus' then true
          when 'presence' then s.share_training_presence
          when 'performance' then s.share_performance_stats
          when 'trophies' then s.share_trophy_cabinet
          when 'activity' then s.share_recent_activity
          when 'goals' then s.share_goals
          when 'running_prs' then s.share_running_prs
          when 'strength_prs' then s.share_strength_prs
          when 'workout_totals' then s.share_workout_totals
          else false
        end
        and (
          case section_name
            when 'training_focus' then s.training_focus_visibility
            when 'presence' then s.training_presence_visibility
            when 'performance' then s.performance_stats_visibility
            when 'trophies' then s.trophy_cabinet_visibility
            when 'activity' then s.recent_activity_visibility
            when 'goals' then s.goals_visibility
            when 'running_prs' then s.running_prs_visibility
            when 'strength_prs' then s.strength_prs_visibility
            when 'workout_totals' then s.performance_stats_visibility
            else 'private'
          end = 'public'
          or (
            private.are_friends(owner_id) and
            case section_name
              when 'training_focus' then s.training_focus_visibility
              when 'presence' then s.training_presence_visibility
              when 'performance' then s.performance_stats_visibility
              when 'trophies' then s.trophy_cabinet_visibility
              when 'activity' then s.recent_activity_visibility
              when 'goals' then s.goals_visibility
              when 'running_prs' then s.running_prs_visibility
              when 'strength_prs' then s.strength_prs_visibility
              when 'workout_totals' then s.performance_stats_visibility
              else 'private'
            end = 'friends'
          )
        )
    )
  );
$function$;
