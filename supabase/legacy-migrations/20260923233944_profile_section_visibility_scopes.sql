-- Per-section social visibility scopes for profile setup.
-- Values: private (Off), friends, public.

alter table public.profile_social_settings
  add column if not exists training_presence_visibility text not null default 'private'
    check (training_presence_visibility in ('private','friends','public')),
  add column if not exists performance_stats_visibility text not null default 'private'
    check (performance_stats_visibility in ('private','friends','public')),
  add column if not exists trophy_cabinet_visibility text not null default 'private'
    check (trophy_cabinet_visibility in ('private','friends','public')),
  add column if not exists recent_activity_visibility text not null default 'private'
    check (recent_activity_visibility in ('private','friends','public'));

update public.profile_social_settings
set
  training_presence_visibility = case
    when share_training_presence then profile_visibility else 'private'
  end,
  performance_stats_visibility = case
    when share_performance_stats then profile_visibility else 'private'
  end,
  trophy_cabinet_visibility = case
    when share_trophy_cabinet then profile_visibility else 'private'
  end,
  recent_activity_visibility = case
    when share_recent_activity then profile_visibility else 'private'
  end;

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
            when 'goals' then case when s.share_goals then s.profile_visibility else 'private' end
            when 'running_prs' then case when s.share_running_prs then s.profile_visibility else 'private' end
            when 'strength_prs' then case when s.share_strength_prs then s.profile_visibility else 'private' end
            when 'workout_totals' then case when s.share_workout_totals then s.profile_visibility else 'private' end
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
              when 'goals' then case when s.share_goals then s.profile_visibility else 'private' end
              when 'running_prs' then case when s.share_running_prs then s.profile_visibility else 'private' end
              when 'strength_prs' then case when s.share_strength_prs then s.profile_visibility else 'private' end
              when 'workout_totals' then case when s.share_workout_totals then s.profile_visibility else 'private' end
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
