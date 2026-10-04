alter table if exists public.public_trails
  add column if not exists route_shape text,
  add column if not exists surface_summary text,
  add column if not exists difficulty text,
  add column if not exists osm_description text,
  add column if not exists website text,
  add column if not exists estimated_run_seconds double precision,
  add column if not exists estimated_walk_seconds double precision,
  add column if not exists elevation_gain_meters double precision,
  add column if not exists elevation_loss_meters double precision,
  add column if not exists min_elevation_meters double precision,
  add column if not exists max_elevation_meters double precision,
  add column if not exists average_grade_percent double precision,
  add column if not exists max_grade_percent double precision,
  add column if not exists elevation_profile jsonb not null default '[]'::jsonb;

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

drop trigger if exists public_trails_derived_metadata on public.public_trails;
create trigger public_trails_derived_metadata
before insert or update of coordinates, distance_kilometers, route_shape, estimated_run_seconds, estimated_walk_seconds
on public.public_trails
for each row
execute function public.set_public_trail_derived_metadata();

update public.public_trails
set coordinates = coordinates
where coordinates is not null;

create or replace function public.similar_public_trails(
  p_trail_id uuid,
  p_limit integer default 10
)
returns setof public.public_trails
language sql
stable
security invoker
set search_path = ''
as $function$
  with target as (
    select *
    from public.public_trails
    where id = p_trail_id
    limit 1
  )
  select candidate.*
  from public.public_trails candidate
  cross join target
  where candidate.id <> target.id
  order by
    abs(
      ln(
        greatest(candidate.distance_kilometers, 0.1) /
        greatest(target.distance_kilometers, 0.1)
      )
    ) * 5.0
    + case
        when candidate.route_shape is not distinct from target.route_shape then 0.0
        else 0.55
      end
    + case
        when candidate.difficulty is null or target.difficulty is null then 0.12
        when candidate.difficulty = target.difficulty then 0.0
        else 0.45
      end
    + case
        when candidate.surface_summary is null or target.surface_summary is null then 0.08
        when candidate.surface_summary = target.surface_summary then 0.0
        else 0.28
      end
    + case
        when candidate.elevation_gain_meters is null or target.elevation_gain_meters is null then 0.1
        else least(abs(candidate.elevation_gain_meters - target.elevation_gain_meters) / 600.0, 1.0)
      end,
    candidate.athlth_verified desc,
    candidate.distance_kilometers asc,
    candidate.id asc
  limit least(greatest(coalesce(p_limit, 10), 1), 10);
$function$;

revoke all on function public.similar_public_trails(uuid, integer) from public, anon;
grant execute on function public.similar_public_trails(uuid, integer) to authenticated;
