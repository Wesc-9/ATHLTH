alter table public.public_trail_fetch_cells
    alter column fetched_at drop not null,
    alter column fetched_at drop default;

alter table public.public_trail_fetch_cells
    add column if not exists refresh_started_at timestamptz,
    add column if not exists last_error text,
    add column if not exists last_success_count integer;

create index if not exists public_trail_fetch_cells_refresh_idx
    on public.public_trail_fetch_cells(refresh_started_at);
