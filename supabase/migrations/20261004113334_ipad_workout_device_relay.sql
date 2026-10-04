create table if not exists public.workout_device_commands (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_request_id uuid not null,
  source_device text not null check (source_device in ('ipad', 'iphone')),
  target_device text not null check (target_device in ('iphone', 'apple_watch')),
  command_kind text not null check (command_kind in ('run', 'walk', 'strength')),
  payload jsonb not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '10 minutes'),
  claimed_at timestamptz,
  claimed_by_device_id text,
  completed_at timestamptz,
  failed_at timestamptz,
  failure_message text,
  unique (user_id, client_request_id)
);

create index if not exists workout_device_commands_pending_idx
  on public.workout_device_commands (user_id, created_at)
  where claimed_at is null
    and completed_at is null
    and failed_at is null;

alter table public.workout_device_commands enable row level security;

revoke all on table public.workout_device_commands from anon;
grant select, insert, update, delete on table public.workout_device_commands to authenticated;

drop policy if exists "Users can read own workout device commands"
  on public.workout_device_commands;
create policy "Users can read own workout device commands"
  on public.workout_device_commands
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert own workout device commands"
  on public.workout_device_commands;
create policy "Users can insert own workout device commands"
  on public.workout_device_commands
  for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and source_device in ('ipad', 'iphone')
    and target_device in ('iphone', 'apple_watch')
  );

drop policy if exists "Users can update own workout device commands"
  on public.workout_device_commands;
create policy "Users can update own workout device commands"
  on public.workout_device_commands
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete own workout device commands"
  on public.workout_device_commands;
create policy "Users can delete own workout device commands"
  on public.workout_device_commands
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.claim_next_workout_device_command(
  p_device_id text
)
returns setof public.workout_device_commands
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := (select auth.uid());
  picked uuid;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if nullif(btrim(p_device_id), '') is null
     or char_length(p_device_id) > 200 then
    raise exception 'Invalid device identifier';
  end if;

  update public.workout_device_commands c
  set claimed_at = now(),
      claimed_by_device_id = p_device_id
  where c.id = (
    select q.id
    from public.workout_device_commands q
    where q.user_id = actor
      and q.claimed_at is null
      and q.completed_at is null
      and q.failed_at is null
      and q.expires_at > now()
    order by q.created_at asc
    limit 1
    for update skip locked
  )
  returning c.id into picked;

  if picked is null then
    return;
  end if;

  return query
  select c.*
  from public.workout_device_commands c
  where c.id = picked
    and c.user_id = actor;
end;
$function$;

revoke all on function public.claim_next_workout_device_command(text)
  from public, anon;
grant execute on function public.claim_next_workout_device_command(text)
  to authenticated;

do $$
begin
  if exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'workout_device_commands'
  ) then
    alter publication supabase_realtime
      add table public.workout_device_commands;
  end if;
end
$$;
