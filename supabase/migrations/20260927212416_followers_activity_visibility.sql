-- Treat the legacy 'friends' visibility token as follower-scoped visibility.
create or replace function private.is_following(owner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $function$
  select exists (
    select 1
    from public.profile_follows f
    where f.follower_id = (select auth.uid())
      and f.following_id = owner_id
  );
$function$;

revoke all on function private.is_following(uuid)
from public, anon, authenticated;

create or replace function private.can_view_social_section(owner_id uuid, section_name text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $function$
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
              when 'running_prs' then s.running_prs_visibility
              when 'strength_prs' then s.strength_prs_visibility
              when 'workout_totals' then s.performance_stats_visibility
              else 'private'
            end
            from public.profile_social_settings s
            where s.user_id = owner_id
          ), 'private') = 'friends'
          and private.is_following(owner_id)
        )
      )
    );
$function$;

create or replace function private.can_view_activity(
  owner_id uuid,
  activity_visibility text,
  activity_kind text,
  activity_metadata jsonb
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $function$
  select
    (select auth.uid()) = owner_id
    or (
      (select auth.uid()) is not null
      and not private.is_blocked(owner_id)
      and (
        activity_visibility = 'public'
        or (
          activity_visibility = 'friends'
          and private.is_following(owner_id)
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
