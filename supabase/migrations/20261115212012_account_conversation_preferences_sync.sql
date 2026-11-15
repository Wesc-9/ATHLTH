-- Per-conversation preferences are private account state.
-- Independent clocks preserve offline pin/unpin and archive/unarchive.
create table if not exists public.athlth_account_conversation_preferences (
  user_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid not null,
  pinned_at timestamptz,
  unpinned_at timestamptz,
  archived_at timestamptz,
  unarchived_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(user_id, conversation_id)
);
alter table public.athlth_account_conversation_preferences enable row level security;
create policy "Read own conversation preferences" on public.athlth_account_conversation_preferences
 for select to authenticated using ((select auth.uid()) = user_id);
create policy "Insert own conversation preferences" on public.athlth_account_conversation_preferences
 for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Update own conversation preferences" on public.athlth_account_conversation_preferences
 for update to authenticated using ((select auth.uid()) = user_id)
 with check ((select auth.uid()) = user_id);
grant select, insert, update on public.athlth_account_conversation_preferences to authenticated;
create function public.athlth_conversation_preference_monotonic_update()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if new.user_id <> old.user_id or new.conversation_id <> old.conversation_id then
    raise exception 'conversation preference identity is immutable';
  end if;
  new.pinned_at := greatest(new.pinned_at, old.pinned_at);
  new.unpinned_at := greatest(new.unpinned_at, old.unpinned_at);
  new.archived_at := greatest(new.archived_at, old.archived_at);
  new.unarchived_at := greatest(new.unarchived_at, old.unarchived_at);
  new.updated_at := now();
  return new;
end;
$$;
create trigger athlth_conversation_preference_monotonic_update
before update on public.athlth_account_conversation_preferences
for each row execute function public.athlth_conversation_preference_monotonic_update();
revoke all on function public.athlth_conversation_preference_monotonic_update() from public;
