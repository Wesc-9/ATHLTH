-- Preserve a compact route snapshot on community events so every
-- participant can see the course even when the owner's route is private.
alter table public.community_events
  add column if not exists route_coordinates jsonb,
  add column if not exists route_distance_kilometers double precision,
  add column if not exists route_elevation_gain_meters double precision,
  add column if not exists route_start_name text,
  add column if not exists route_end_name text;

alter table public.community_events
  drop constraint if exists community_events_route_distance_check;

alter table public.community_events
  add constraint community_events_route_distance_check
  check (
    route_distance_kilometers is null
    or route_distance_kilometers >= 0
  );

alter table public.community_events
  drop constraint if exists community_events_route_coordinates_size_check;

alter table public.community_events
  add constraint community_events_route_coordinates_size_check
  check (
    route_coordinates is null
    or octet_length(route_coordinates::text) <= 1048576
  );
