alter table public.public_trails
  drop constraint if exists public_trails_source_check;

alter table public.public_trails
  add constraint public_trails_source_check
  check (
    source in (
      'openstreetmap',
      'kartverket_turrutebasen'
    )
  );

create index if not exists public_trails_source_idx
  on public.public_trails (source);
