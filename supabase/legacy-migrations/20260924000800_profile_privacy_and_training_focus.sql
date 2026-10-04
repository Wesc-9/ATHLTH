-- Privacy-first profile defaults and scoped training-focus sharing.

alter table public.profile_social_settings
  alter column profile_visibility set default 'private',
  alter column discoverable set default false;

alter table public.profile_social_settings
  add column if not exists training_focus_visibility text not null default 'private'
    check (training_focus_visibility in ('private','friends','public'));

create table if not exists public.social_training_focus (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  focus text not null
    check (focus in ('running','strength','hybrid','walking','generalFitness','recovery')),
  updated_at timestamptz not null default now()
);

alter table public.social_training_focus enable row level security;

grant select, insert, update on public.social_training_focus to authenticated;

create or replace function private.can_view_social_section(
  owner_id uuid,
  section_name text
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
        coalesce((
          select case section_name
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
          end
          from public.profile_social_settings s
          where s.user_id = owner_id
        ), 'private') = 'public'
        or (
          coalesce((
            select case section_name
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
            end
            from public.profile_social_settings s
            where s.user_id = owner_id
          ), 'private') = 'friends'
          and private.are_friends(owner_id)
        )
      )
    );
$function$;

drop policy if exists social_training_focus_select_allowed
  on public.social_training_focus;
create policy social_training_focus_select_allowed
  on public.social_training_focus
  for select
  to authenticated
  using (private.can_view_social_section(user_id, 'training_focus'));

drop policy if exists social_training_focus_insert_own
  on public.social_training_focus;
create policy social_training_focus_insert_own
  on public.social_training_focus
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists social_training_focus_update_own
  on public.social_training_focus;
create policy social_training_focus_update_own
  on public.social_training_focus
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop trigger if exists social_training_focus_updated_at
  on public.social_training_focus;
create trigger social_training_focus_updated_at
before update on public.social_training_focus
for each row execute function public.set_updated_at();

update public.profile_social_settings
set profile_visibility = 'private',
    discoverable = false
where profile_visibility = 'friends'
  and discoverable = true
  and training_focus_visibility = 'private'
  and training_presence_visibility = 'private'
  and performance_stats_visibility = 'private'
  and trophy_cabinet_visibility = 'private'
  and recent_activity_visibility = 'private'
  and goals_visibility = 'private'
  and running_prs_visibility = 'private'
  and strength_prs_visibility = 'private'
  and share_training_presence = false
  and share_performance_stats = false
  and share_trophy_cabinet = false
  and share_goals = false
  and share_recent_activity = false
  and share_running_prs = false
  and share_strength_prs = false
  and share_workout_totals = false;
