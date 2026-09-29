-- Keep online state separate from "Training now" so the two privacy controls never widen each other.

create table if not exists public.user_online_presence (
    user_id uuid primary key references public.profiles(id) on delete cascade,
    last_seen_at timestamptz not null default now(),
    online_until timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists user_online_presence_until_idx
    on public.user_online_presence(online_until desc);

alter table public.user_online_presence enable row level security;

revoke all on public.user_online_presence from anon;
revoke all on public.user_online_presence from authenticated;
grant select, insert, update(last_seen_at, online_until, updated_at)
    on public.user_online_presence to authenticated;

drop policy if exists "presence visible by privacy"
on public.social_presence;

drop policy if exists "online presence owner insert"
on public.user_online_presence;
create policy "online presence owner insert"
on public.user_online_presence
for insert
to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists "online presence owner update"
on public.user_online_presence;
create policy "online presence owner update"
on public.user_online_presence
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "online presence viewer select"
on public.user_online_presence;
create policy "online presence viewer select"
on public.user_online_presence
for select
to authenticated
using (private.can_view_social_presence(user_id));

do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'user_online_presence'
    ) then
        alter publication supabase_realtime add table public.user_online_presence;
    end if;
end
$$;
