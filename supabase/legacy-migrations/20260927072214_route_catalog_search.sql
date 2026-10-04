-- Filter and order the full catalogue on the server, returning only 50
-- lightweight records. Invoker security preserves community_routes RLS.
create or replace function public.search_route_catalog(
  p_query text default '', p_sort text default 'Newest', p_length integer default 0,
  p_latitude double precision default null, p_longitude double precision default null,
  p_offset integer default 0
)
returns table (
  id uuid, title text, distance_kilometers double precision,
  elevation_gain_meters double precision, start_name text, end_name text,
  center_latitude double precision, center_longitude double precision,
  created_at timestamptz
)
language sql stable security invoker set search_path = ''
as $function$
  select r.id, r.title, r.distance_kilometers, r.elevation_gain_meters,
    r.start_name, r.end_name, r.center_latitude, r.center_longitude, r.created_at
  from public.community_routes r
  where r.visibility = 'public'
    and (coalesce(p_query, '') = '' or strpos(
      lower(r.title || ' ' || coalesce(r.start_name, '') || ' ' || coalesce(r.end_name, '')),
      lower(left(p_query, 200))) > 0)
    and case p_length
      when 1 then r.distance_kilometers < 5
      when 2 then r.distance_kilometers >= 5 and r.distance_kilometers < 10
      when 3 then r.distance_kilometers >= 10 and r.distance_kilometers < 21.1
      when 4 then r.distance_kilometers >= 21.1
      else true end
  order by
    case when p_sort = 'Nearest' and p_latitude between -90 and 90 and p_longitude between -180 and 180 then
      acos(least(1.0, greatest(-1.0,
        sin(radians(p_latitude)) * sin(radians(r.center_latitude)) +
        cos(radians(p_latitude)) * cos(radians(r.center_latitude)) *
        cos(radians(r.center_longitude - p_longitude))))) end asc nulls last,
    case when p_sort = 'Newest' then r.created_at end desc nulls last,
    case when p_sort = 'Shortest' then r.distance_kilometers end asc nulls last,
    case when p_sort = 'Longest' then r.distance_kilometers end desc nulls last,
    case when p_sort = 'Least climbing' then r.elevation_gain_meters end asc nulls last,
    case when p_sort = 'Most climbing' then r.elevation_gain_meters end desc nulls last,
    lower(r.title) asc, r.id asc
  limit 50 offset greatest(coalesce(p_offset, 0), 0);
$function$;
revoke all on function public.search_route_catalog(text,text,integer,double precision,double precision,integer) from public, anon;
grant execute on function public.search_route_catalog(text,text,integer,double precision,double precision,integer) to authenticated;
