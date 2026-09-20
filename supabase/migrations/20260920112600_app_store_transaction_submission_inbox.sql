create table public.app_store_transaction_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  transaction_id text not null,
  original_transaction_id text not null,
  product_id text not null,
  app_account_token uuid,
  signed_transaction_info text not null,
  status text not null default 'pending',
  submitted_at timestamptz not null default now(),
  processed_at timestamptz,
  verification_error text,
  constraint app_store_transaction_submissions_status_check
    check (status in ('pending', 'verified', 'rejected')),
  unique (user_id, transaction_id)
);

create index app_store_transaction_submissions_user_id_idx
  on public.app_store_transaction_submissions(user_id);

create index app_store_transaction_submissions_status_idx
  on public.app_store_transaction_submissions(status, submitted_at);

alter table public.app_store_transaction_submissions enable row level security;

create policy "app_store_submissions_select_own"
on public.app_store_transaction_submissions
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "app_store_submissions_insert_own"
on public.app_store_transaction_submissions
for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and status = 'pending'
  and processed_at is null
  and verification_error is null
);

grant select, insert on public.app_store_transaction_submissions to authenticated;
