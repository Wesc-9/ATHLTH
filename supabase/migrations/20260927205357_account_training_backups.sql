-- Private, per-device snapshots. A new phone cannot overwrite another phone's copy.
create table public.account_training_backups (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id),
  constraint backup_payload_size check (octet_length(payload::text) <= 22000000),
  constraint backup_payload_version check (payload->>'version' = '1'),
  constraint backup_payload_owner check (lower(payload->>'ownerID') = user_id::text)
);
alter table public.account_training_backups enable row level security;
revoke all on public.account_training_backups from public, anon;
grant select, insert, update, delete on public.account_training_backups to authenticated;
create policy backup_select on public.account_training_backups for select to authenticated using ((select auth.uid()) = user_id);
create policy backup_insert on public.account_training_backups for insert to authenticated with check ((select auth.uid()) = user_id);
create policy backup_update on public.account_training_backups for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy backup_delete on public.account_training_backups for delete to authenticated using ((select auth.uid()) = user_id);
