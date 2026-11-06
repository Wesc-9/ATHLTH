-- Private, explicit opt-in Ghost Race spectator relay for the same account.
-- Historical and target-Ghost course geometry is sensitive location data:
-- NEVER expose these rows to other accounts, followers or public challenges.
-- The publisher is the signed-in iPhone (including Watch-mirrored sessions).
-- Expiry and a frequent purge keep abandoned races from persisting.
create table if not exists public.private_active_ghost_ipad_status (
    user_id uuid primary key references auth.users(id) on delete cascade,
    snapshot jsonb not null check (
        jsonb_typeof(snapshot) = 'object'
        and octet_length(snapshot::text) <= 65536
    ),
    updated_at timestamptz not null default now(),
    expires_at timestamptz not null default (now() + interval '65 seconds'),
    constraint private_active_ghost_ipad_expiry_bounded check (
        expires_at >= updated_at
        and expires_at <= updated_at + interval '120 seconds'
    )
);

create index if not exists private_active_ghost_ipad_status_expiry_idx
    on public.private_active_ghost_ipad_status (expires_at);

alter table public.private_active_ghost_ipad_status enable row level security;

revoke all on public.private_active_ghost_ipad_status from public, anon;
grant select, insert, update, delete
    on public.private_active_ghost_ipad_status to authenticated;

drop policy if exists "Own private active Ghost read" on public.private_active_ghost_ipad_status;
create policy "Own private active Ghost read"
on public.private_active_ghost_ipad_status for select to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Own private active Ghost insert" on public.private_active_ghost_ipad_status;
create policy "Own private active Ghost insert"
on public.private_active_ghost_ipad_status for insert to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Own private active Ghost update" on public.private_active_ghost_ipad_status;
create policy "Own private active Ghost update"
on public.private_active_ghost_ipad_status for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Own private active Ghost delete" on public.private_active_ghost_ipad_status;
create policy "Own private active Ghost delete"
on public.private_active_ghost_ipad_status for delete to authenticated
using ((select auth.uid()) = user_id);

-- pg_cron is used by the existing private strength spectator service.
select cron.schedule(
    'athlth-purge-expired-private-ghost-ipad',
    '* * * * *',
    $$delete from public.private_active_ghost_ipad_status
      where expires_at < now();$$
);
