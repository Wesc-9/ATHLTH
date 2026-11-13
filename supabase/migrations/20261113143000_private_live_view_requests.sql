-- iPad may request viewing, but only the recording iPhone may grant a
-- session-local permission in memory. A request row never authorizes a
-- workout snapshot by itself.
create table if not exists public.private_live_view_requests (
    user_id uuid primary key references auth.users(id) on delete cascade,
    request_id uuid not null,
    requested_at timestamptz not null default now(),
    expires_at timestamptz not null,
    status text not null default 'pending'
        check (status in ('pending', 'approved', 'denied')),
    responded_at timestamptz,
    approved_session_id uuid,
    constraint private_live_view_requests_valid_window
        check (expires_at > requested_at and expires_at <= requested_at + interval '5 minutes')
);
create index if not exists private_live_view_requests_expires_idx
    on public.private_live_view_requests (expires_at);
alter table public.private_live_view_requests enable row level security;
revoke all on public.private_live_view_requests from anon;
grant select, insert, update, delete on public.private_live_view_requests to authenticated;
-- Idempotent on environments where the remote migration was already applied.
do $$
begin
    if not exists (select 1 from pg_policies
        where schemaname = 'public' and tablename = 'private_live_view_requests'
        and policyname = 'Own live view request select') then
        create policy "Own live view request select"
            on public.private_live_view_requests for select to authenticated
            using (user_id = (select auth.uid()));
    end if;
    if not exists (select 1 from pg_policies
        where schemaname = 'public' and tablename = 'private_live_view_requests'
        and policyname = 'Own live view request insert') then
        create policy "Own live view request insert"
            on public.private_live_view_requests for insert to authenticated
            with check (user_id = (select auth.uid()));
    end if;
    if not exists (select 1 from pg_policies
        where schemaname = 'public' and tablename = 'private_live_view_requests'
        and policyname = 'Own live view request update') then
        create policy "Own live view request update"
            on public.private_live_view_requests for update to authenticated
            using (user_id = (select auth.uid()))
            with check (user_id = (select auth.uid()));
    end if;
    if not exists (select 1 from pg_policies
        where schemaname = 'public' and tablename = 'private_live_view_requests'
        and policyname = 'Own live view request delete') then
        create policy "Own live view request delete"
            on public.private_live_view_requests for delete to authenticated
            using (user_id = (select auth.uid()));
    end if;
end $$;
comment on table public.private_live_view_requests is
    'Ephemeral same-account request notification. The iPhone must grant each exact active workout locally before publishing private_active_workout_status.';
