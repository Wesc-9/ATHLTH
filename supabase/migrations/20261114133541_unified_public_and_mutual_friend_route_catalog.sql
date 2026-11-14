-- Metadata-only browsing with RLS-enforced mutual friend visibility.
CREATE OR REPLACE FUNCTION public.search_shared_route_library(p_query text DEFAULT ''::text, p_sort text DEFAULT 'Newest'::text, p_length integer DEFAULT 0, p_latitude double precision DEFAULT NULL::double precision, p_longitude double precision DEFAULT NULL::double precision, p_offset integer DEFAULT 0, p_friends_only boolean DEFAULT false, p_min_length double precision DEFAULT 0, p_max_length double precision DEFAULT 20)
 RETURNS TABLE(id uuid, owner_id uuid, title text, distance_kilometers double precision, elevation_gain_meters double precision, start_name text, end_name text, center_latitude double precision, center_longitude double precision, created_at timestamp with time zone, source_type text, visibility text, source_label text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
    with eligible as (
        select
            r.id, r.owner_id, r.title, r.distance_kilometers,
            r.elevation_gain_meters, r.start_name, r.end_name,
            r.center_latitude, r.center_longitude, r.created_at,
            'community'::text as source_type, r.visibility::text as visibility,
            r.route_source::text as source_label
        from public.community_routes r
        where
            (r.visibility = 'public'
                or (r.visibility = 'friends' and r.owner_id <> (select auth.uid())
                    and exists (
                        select 1 from public.profile_follows f
                        where f.follower_id = (select auth.uid())
                          and f.following_id = r.owner_id
                    )
                    and exists (
                        select 1 from public.profile_follows f
                        where f.follower_id = r.owner_id
                          and f.following_id = (select auth.uid())
                    )
                )
            )
            and (not coalesce(p_friends_only,false)
                 or (
                    r.owner_id <> (select auth.uid())
                    and exists (
                        select 1 from public.profile_follows f
                        where f.follower_id = (select auth.uid())
                          and f.following_id = r.owner_id
                    )
                    and exists (
                        select 1 from public.profile_follows f
                        where f.follower_id = r.owner_id
                          and f.following_id = (select auth.uid())
                    )
                 ))

        union all

        select
            t.id,
            '00000000-0000-0000-0000-000000000001'::uuid as owner_id,
            t.name::text as title,
            t.distance_kilometers,
            t.elevation_gain_meters,
            t.reference::text as start_name,
            null::text as end_name,
            t.center_latitude,
            t.center_longitude,
            t.created_at,
            'public_trail'::text as source_type,
            'public'::text as visibility,
            t.source::text as source_label
        from public.public_trails t
        where not coalesce(p_friends_only, false)
          and t.distance_kilometers between 0.5 and 80
    ),
    filtered as (
        select *
        from eligible e
        where
            (coalesce(p_query, '') = '' or strpos(
               lower(e.title || ' ' || coalesce(e.start_name, '') || ' ' ||
                    coalesce(e.end_name, '')),
               lower(left(p_query,200))
            ) > 0)
            and case p_length
                when 1 then e.distance_kilometers < 3
                when 2 then e.distance_kilometers >= 3 and e.distance_kilometers < 5
                when 3 then e.distance_kilometers >= 5 and e.distance_kilometers < 10
                when 4 then e.distance_kilometers >= 10 and e.distance_kilometers < 20
                when 5 then e.distance_kilometers >= 20
                when 6 then e.distance_kilometers between
                    greatest(0,least(coalesce(p_min_length,0),coalesce(p_max_length,20)))
                    and greatest(coalesce(p_min_length,0),coalesce(p_max_length,20))
                else true end
    )
    select
        e.id, e.owner_id, e.title, e.distance_kilometers,
        e.elevation_gain_meters, e.start_name, e.end_name,
        e.center_latitude, e.center_longitude, e.created_at,
        e.source_type, e.visibility, e.source_label
    from filtered e
    order by
        case when p_sort = 'Nearest' and
            p_latitude between -90 and 90 and p_longitude between -180 and 180 then
            acos(least(1.0,greatest(-1.0,
                sin(radians(p_latitude)) * sin(radians(e.center_latitude)) +
                cos(radians(p_latitude)) * cos(radians(e.center_latitude)) *
                cos(radians(e.center_longitude - p_longitude))
            ))) end asc nulls last,
        case when p_sort = 'Newest' then e.created_at end desc nulls last,
        case when p_sort = 'Shortest' then e.distance_kilometers end asc nulls last,
        case when p_sort = 'Longest' then e.distance_kilometers end desc nulls last,
        case when p_sort = 'Least climbing' then e.elevation_gain_meters end asc nulls last,
        case when p_sort = 'Most climbing' then e.elevation_gain_meters end desc nulls last,
        lower(e.title) asc, e.source_type asc, e.id asc
    limit 50 offset greatest(0,least(coalesce(p_offset,0),1000000));
$function$
;

revoke all on function public.search_shared_route_library(
  text,text,integer,double precision,double precision,integer,boolean,double precision,double precision
) from public, anon;
grant execute on function public.search_shared_route_library(
  text,text,integer,double precision,double precision,integer,boolean,double precision,double precision
) to authenticated;
create index if not exists public_trails_browse_created_at_idx
  on public.public_trails (created_at desc);
