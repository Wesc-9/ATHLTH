create table if not exists public.app_feature_flags (
  key text primary key,
  enabled boolean not null default false,
  description text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.app_feature_flags enable row level security;

grant select on table public.app_feature_flags to authenticated;
grant update (enabled, updated_at) on table public.app_feature_flags to authenticated;

drop policy if exists "app_feature_flags_read" on public.app_feature_flags;
create policy "app_feature_flags_read"
  on public.app_feature_flags
  for select
  to authenticated
  using (true);

drop policy if exists "app_feature_flags_admin_update" on public.app_feature_flags;
create policy "app_feature_flags_admin_update"
  on public.app_feature_flags
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.account_roles ar
      where ar.user_id = (select auth.uid())
        and ar.role in ('admin', 'owner')
    )
  )
  with check (
    exists (
      select 1
      from public.account_roles ar
      where ar.user_id = (select auth.uid())
        and ar.role in ('admin', 'owner')
    )
  );

insert into public.app_feature_flags (key, enabled, description)
values (
  'activity_center_ai_workout_hero',
  false,
  'When enabled, Activity Center may use the AI-generated workout hero. When disabled, Route Ribbon is the only running-route visual.'
)
on conflict (key) do nothing;
