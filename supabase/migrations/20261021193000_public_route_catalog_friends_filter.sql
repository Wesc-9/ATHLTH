-- Public route discovery keeps the same public-only visibility guard as
-- search_route_catalog, and adds a server-side mutual-friends filter before
-- ordering and pagination. No private/friends-only routes are returned.
create or replace function public.search_public_route_catalog(
  p_query text default '',
  p_sort text default 'Newest',
  p_length integer default 0,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_offset integer default 0,
  p_friends_only boolean default false,
  p_min_length double precision default 0,
  p_max_length double precision default 20
)
returns table (
  id uuid, owner_id uuid, title text, distance_kilometers double precision,
  elevation_gain_meters double precision, start_name text, end_name text,
  center_latitude double precision, center_longitude double precision,
  created_at timestamptz
)
language sql stable security invoker set search_path = ''
as $function$
  select r.id, r.owner_id, r.title, r.distance_kilometers,
    r.elevation_gain_meters, r.start_name, r.end_name,
    r.center_latitude, r.center_longitude, r.created_at
  from public.community_routes r
  where r.visibility = 'public'
    and (
      not coalesce(p_friends_only, false)
      or (
        r.owner_id <> (select auth.uid())
        and exists (
          select 1 from public.profile_follows following
          where following.follower_id = (select auth.uid())
            and following.following_id = r.owner_id
        )
        and exists (
          select 1 from public.profile_follows follower
          where follower.follower_id = r.owner_id
            and follower.following_id = (select auth.uid())
        )
      )
    )
    and (coalesce(p_query, '') = '' or strpos(
      lower(r.title || ' ' || coalesce(r.start_name, '') || ' ' || coalesce(r.end_name, '')),
      lower(left(p_query, 200))) > 0)
    and case p_length
      when 1 then r.distance_kilometers < 3
      when 2 then r.distance_kilometers >= 3 and r.distance_kilometers < 5
      when 3 then r.distance_kilometers >= 5 and r.distance_kilometers < 10
      when 4 then r.distance_kilometers >= 10 and r.distance_kilometers < 20
      when 5 then r.distance_kilometers >= 20
      when 6 then r.distance_kilometers between
        greatest(0, least(coalesce(p_min_length, 0), coalesce(p_max_length, 20))) and
        greatest(coalesce(p_min_length, 0), coalesce(p_max_length, 20))
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

revoke all on function public.search_public_route_catalog(
  text, text, integer, double precision, double precision, integer, boolean,
  double precision, double precision
) from public, anon;
grant execute on function public.search_public_route_catalog(
  text, text, integer, double precision, double precision, integer, boolean,
  double precision, double precision
) to authenticated;
