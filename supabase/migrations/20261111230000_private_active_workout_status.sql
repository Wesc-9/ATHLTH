-- Private account-only spectator summary for the active phone workout.
-- No GPS coordinates, route geometry, HealthKit records, pulse samples or
-- social sharing. A connected iPad reads the same user's latest summary.
create table if not exists public.private_active_workout_status (
    user_id uuid primary key references auth.users(id) on delete cascade,
    snapshot jsonb not null check (
        jsonb_typeof(snapshot) = 'object'
        and octet_length(snapshot::text) <= 16384
    ),
    updated_at timestamptz not null default now(),
    expires_at timestamptz not null default (now() + interval '30 seconds'),
    constraint private_active_workout_status_expiry_bounded check (
        expires_at >= updated_at and
        expires_at <= updated_at + interval '60 seconds'
    )
);

create index if not exists private_active_workout_status_expiry_idx
    on public.private_active_workout_status (expires_at);

alter table public.private_active_workout_status enable row level security;
revoke all on public.private_active_workout_status from public, anon;
grant select, insert, update, delete on public.private_active_workout_status to authenticated;

create policy "Own workout spectator read"
    on public.private_active_workout_status for select to authenticated
    using (user_id = (select auth.uid()));
create policy "Own workout spectator insert"
    on public.private_active_workout_status for insert to authenticated
    with check (user_id = (select auth.uid()));
create policy "Own workout spectator update"
    on public.private_active_workout_status for update to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));
create policy "Own workout spectator delete"
    on public.private_active_workout_status for delete to authenticated
    using (user_id = (select auth.uid()));
