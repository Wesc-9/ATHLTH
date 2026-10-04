alter table if exists public.public_trails
  add column if not exists min_latitude double precision,
  add column if not exists max_latitude double precision,
  add column if not exists min_longitude double precision,
  add column if not exists max_longitude double precision;

create or replace function public.set_public_trail_derived_metadata()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  point_count integer;
  first_lat double precision;
  first_lon double precision;
  last_lat double precision;
  last_lon double precision;
  endpoint_distance_m double precision;
  loop_threshold_m double precision;
begin
  point_count := jsonb_array_length(coalesce(new.coordinates, '[]'::jsonb));

  if point_count >= 1 then
    select
      min((point->>'latitude')::double precision),
      max((point->>'latitude')::double precision),
      min((point->>'longitude')::double precision),
      max((point->>'longitude')::double precision)
    into
      new.min_latitude,
      new.max_latitude,
      new.min_longitude,
      new.max_longitude
    from jsonb_array_elements(new.coordinates) as point;
  end if;

  if point_count >= 2 then
    first_lat := nullif(new.coordinates->0->>'latitude', '')::double precision;
    first_lon := nullif(new.coordinates->0->>'longitude', '')::double precision;
    last_lat := nullif(new.coordinates->(point_count - 1)->>'latitude', '')::double precision;
    last_lon := nullif(new.coordinates->(point_count - 1)->>'longitude', '')::double precision;

    if first_lat is not null and first_lon is not null and last_lat is not null and last_lon is not null then
      endpoint_distance_m :=
        6371000.0 * acos(
          least(1.0, greatest(-1.0,
            sin(radians(first_lat)) * sin(radians(last_lat)) +
            cos(radians(first_lat)) * cos(radians(last_lat)) *
            cos(radians(last_lon - first_lon))
          ))
        );
      loop_threshold_m := greatest(250.0, least(700.0, new.distance_kilometers * 1000.0 * 0.06));
      new.route_shape := case
        when endpoint_distance_m <= loop_threshold_m then 'Loop'
        else coalesce(new.route_shape, 'Point to point')
      end;
    end if;
  end if;

  if new.estimated_run_seconds is null and new.distance_kilometers > 0 then
    new.estimated_run_seconds := new.distance_kilometers * 360.0;
  end if;

  if new.estimated_walk_seconds is null and new.distance_kilometers > 0 then
    new.estimated_walk_seconds := new.distance_kilometers * 720.0;
  end if;

  return new;
end;
$function$;

update public.public_trails
set coordinates = coordinates
where coordinates is not null;

create index if not exists public_trails_bbox_lat_idx
  on public.public_trails (min_latitude, max_latitude);

create index if not exists public_trails_bbox_lon_idx
  on public.public_trails (min_longitude, max_longitude);
