-- Per-category social visibility scopes for goals and PR activity.

alter table public.profile_social_settings
  add column if not exists goals_visibility text not null default 'private'
    check (goals_visibility in ('private','friends','public')),
  add column if not exists running_prs_visibility text not null default 'private'
    check (running_prs_visibility in ('private','friends','public')),
  add column if not exists strength_prs_visibility text not null default 'private'
    check (strength_prs_visibility in ('private','friends','public'));

update public.profile_social_settings
set
  goals_visibility = case
    when share_goals then profile_visibility else 'private'
  end,
  running_prs_visibility = case
    when share_running_prs then profile_visibility else 'private'
  end,
  strength_prs_visibility = case
    when share_strength_prs then profile_visibility else 'private'
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
          and private.are_friends(owner_id)
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

drop policy if exists social_activities_select_allowed
  on public.social_activities;
create policy social_activities_select_allowed
  on public.social_activities
  for select
  to authenticated
  using (
    private.can_view_activity(
      actor_id,
      visibility,
      kind,
      metadata
    )
  );

drop policy if exists social_reactions_select_visible
  on public.social_activity_reactions;
create policy social_reactions_select_visible
  on public.social_activity_reactions
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.social_activities a
      where a.id = activity_id
        and private.can_view_activity(
          a.actor_id,
          a.visibility,
          a.kind,
          a.metadata
        )
    )
  );

drop policy if exists social_reactions_insert_own
  on public.social_activity_reactions;
create policy social_reactions_insert_own
  on public.social_activity_reactions
  for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.social_activities a
      where a.id = activity_id
        and private.can_view_activity(
          a.actor_id,
          a.visibility,
          a.kind,
          a.metadata
        )
    )
  );
