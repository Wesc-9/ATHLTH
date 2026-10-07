-- ATHLTH 1.6.7: user-controlled profile header dimming.
-- Stored per profile so the same appearance is shown to other users and across devices.

alter table public.profiles
  add column if not exists header_dim_strength double precision not null default 0;

alter table public.profiles
  drop constraint if exists profiles_header_dim_strength_check;

alter table public.profiles
  add constraint profiles_header_dim_strength_check
  check (
    header_dim_strength >= 0
    and header_dim_strength <= 0.45
  );
