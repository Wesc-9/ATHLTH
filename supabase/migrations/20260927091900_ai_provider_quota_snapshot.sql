create table if not exists public.ai_provider_quota_snapshots (
  provider text not null,
  model text not null,
  limit_requests integer,
  remaining_requests integer,
  reset_requests text,
  last_feature text,
  updated_at timestamptz not null default now(),
  primary key (provider, model)
);

alter table public.ai_provider_quota_snapshots enable row level security;

drop policy if exists ai_quota_select_admin
  on public.ai_provider_quota_snapshots;
create policy ai_quota_select_admin
  on public.ai_provider_quota_snapshots
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.account_roles r
      where r.user_id = (select auth.uid())
        and r.role in ('admin','owner')
    )
  );

grant select on public.ai_provider_quota_snapshots to authenticated;
revoke insert, update, delete on public.ai_provider_quota_snapshots
  from authenticated, anon;
