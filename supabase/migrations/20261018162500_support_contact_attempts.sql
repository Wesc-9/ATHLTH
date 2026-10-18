-- Minimal anti-spam audit for the authenticated ATHLTH contact form.
-- No subject, message, email or health data is stored in this table.
create table if not exists public.support_contact_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  status text not null default 'attempted'
    check (status in ('attempted', 'sent', 'failed'))
);

create index if not exists support_contact_attempts_user_time_idx
  on public.support_contact_attempts (user_id, created_at desc);

alter table public.support_contact_attempts enable row level security;

-- Clients cannot submit impersonated tickets or access other users' attempts.
-- Only the authenticated Edge Function, using the service role, can write.
revoke all on table public.support_contact_attempts from anon, authenticated;
grant select, insert, update on table public.support_contact_attempts to service_role;
