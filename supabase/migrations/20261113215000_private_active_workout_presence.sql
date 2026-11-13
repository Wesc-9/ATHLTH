-- Minimal same-account heartbeat. The existence of a current row means
-- that a workout is underway, but never grants permission to view metrics,
-- location, route, workout title, HealthKit values, or workout controls.
-- Detailed live data remains in private_active_workout_status after iPhone approval.
create table if not exists public.private_active_workout_presence (
    user_id uuid primary key references auth.users(id) on delete cascade,
    source_device text not null check (source_device in ('watch', 'iphone')),
    updated_at timestamptz not null default now(),
    expires_at timestamptz not null default (now() + interval '30 seconds'),
    constraint private_active_workout_presence_window check (
        expires_at >= updated_at and
        expires_at <= updated_at + interval '60 seconds'
    )
);

create index if not exists private_active_workout_presence_expires_idx
    on public.private_active_workout_presence(expires_at);

alter table public.private_active_workout_presence enable row level security;
revoke all on public.private_active_workout_presence from public, anon, authenticated;
grant select, insert, update, delete
    on public.private_active_workout_presence to authenticated;

create policy "Own workout presence read"
    on public.private_active_workout_presence for select to authenticated
    using (user_id = (select auth.uid()));
create policy "Own workout presence insert"
    on public.private_active_workout_presence for insert to authenticated
    with check (user_id = (select auth.uid()));
create policy "Own workout presence update"
    on public.private_active_workout_presence for update to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));
create policy "Own workout presence delete"
    on public.private_active_workout_presence for delete to authenticated
    using (user_id = (select auth.uid()));

comment on table public.private_active_workout_presence is
    'Short-lived private active-workout signal only. Not an approval and never contains live health metrics. User-visible iPad card may request session-scoped consent on iPhone.';
