create table if not exists public.private_workout_device_availability (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (length(device_id) between 1 and 128),
  watch_paired boolean not null,
  watch_installed boolean not null,
  watch_reachable boolean not null,
  observed_at timestamptz not null default now(),
  primary key (user_id, device_id)
);
alter table public.private_workout_device_availability enable row level security;
revoke all on public.private_workout_device_availability from public, anon, authenticated;
grant select, insert, update, delete on public.private_workout_device_availability to authenticated;
create policy workout_device_availability_owner_select on public.private_workout_device_availability for select to authenticated using ((select auth.uid()) = user_id);
create policy workout_device_availability_owner_insert on public.private_workout_device_availability for insert to authenticated with check ((select auth.uid()) = user_id);
create policy workout_device_availability_owner_update on public.private_workout_device_availability for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy workout_device_availability_owner_delete on public.private_workout_device_availability for delete to authenticated using ((select auth.uid()) = user_id);

create table if not exists public.private_workout_control_commands (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null,
  target_device_id text not null check (length(target_device_id) between 1 and 128),
  grant_id uuid not null,
  action text not null check (action in ('pause','resume','end','next','skip_rest')),
  expected_step integer,
  expected_rest_end timestamptz,
  requested_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '25 seconds',
  status text not null default 'pending' check (status in ('pending','claimed','sent','rejected')),
  check (expires_at > requested_at and expires_at <= requested_at + interval '30 seconds')
);
create index if not exists private_workout_control_commands_poll on public.private_workout_control_commands(user_id, target_device_id, status, expires_at);
alter table public.private_workout_control_commands enable row level security;
revoke all on public.private_workout_control_commands from public, anon, authenticated;
grant select, insert, delete on public.private_workout_control_commands to authenticated;
grant update(status) on public.private_workout_control_commands to authenticated;
create policy workout_control_owner_select on public.private_workout_control_commands for select to authenticated using ((select auth.uid()) = user_id);
create policy workout_control_owner_insert on public.private_workout_control_commands for insert to authenticated with check ((select auth.uid()) = user_id and status = 'pending' and expires_at > now() and expires_at <= now() + interval '30 seconds');
create policy workout_control_owner_update on public.private_workout_control_commands for update to authenticated using ((select auth.uid()) = user_id and expires_at > now()) with check ((select auth.uid()) = user_id and status in ('claimed','sent','rejected'));
create policy workout_control_owner_delete on public.private_workout_control_commands for delete to authenticated using ((select auth.uid()) = user_id);
