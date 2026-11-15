-- Account-scoped offline-first notification history. The server preserves
-- read and deletion timestamps even if a stale device writes later.
create table if not exists public.athlth_account_notifications (
  user_id uuid not null references auth.users(id) on delete cascade,
  event_key text not null check (char_length(event_key) between 1 and 240),
  payload_json text not null check (char_length(payload_json) between 2 and 12000),
  read_at timestamptz,
  deleted_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint athlth_account_notifications_pkey primary key (user_id, event_key)
);
create index if not exists athlth_account_notifications_updated_idx
  on public.athlth_account_notifications(user_id, updated_at desc);
alter table public.athlth_account_notifications enable row level security;
create policy "Athlete reads own notifications" on public.athlth_account_notifications
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Athlete inserts own notifications" on public.athlth_account_notifications
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Athlete updates own notifications" on public.athlth_account_notifications
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
grant select, insert, update on public.athlth_account_notifications to authenticated;
create function public.athlth_notification_monotonic_update()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if new.user_id <> old.user_id or new.event_key <> old.event_key then
    raise exception 'notification identity is immutable';
  end if;
  if old.read_at is not null and
     (new.read_at is null or new.read_at < old.read_at) then
    new.read_at := old.read_at;
  end if;
  if old.deleted_at is not null and
     (new.deleted_at is null or new.deleted_at < old.deleted_at) then
    new.deleted_at := old.deleted_at;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger athlth_notification_monotonic_update
before update on public.athlth_account_notifications
for each row execute function public.athlth_notification_monotonic_update();
revoke all on function public.athlth_notification_monotonic_update() from public;
