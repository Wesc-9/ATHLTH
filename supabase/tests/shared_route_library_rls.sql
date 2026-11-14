-- Test on disposable Supabase only. All fixtures roll back.
-- The new public library must not expose private routes, nor a "friends"
-- route to a one-way follower. It must return metadata only.
begin;

insert into auth.users(id) values
 ('19550000-0000-0000-0000-000000000001'),
 ('19550000-0000-0000-0000-000000000002'),
 ('19550000-0000-0000-0000-000000000003');
insert into public.profiles(id) values
 ('19550000-0000-0000-0000-000000000001'),
 ('19550000-0000-0000-0000-000000000002'),
 ('19550000-0000-0000-0000-000000000003')
on conflict(id) do nothing;

insert into public.community_routes
 (id,owner_id,title,visibility,coordinates,distance_kilometers,
  center_latitude,center_longitude)
values
 ('19550000-0000-0000-0000-000000000011',
  '19550000-0000-0000-0000-000000000001',
  'Public test course','public','[]'::jsonb,5,63.4,10.4),
 ('19550000-0000-0000-0000-000000000012',
  '19550000-0000-0000-0000-000000000001',
  'Friends test course','friends','[]'::jsonb,6,63.4,10.4),
 ('19550000-0000-0000-0000-000000000013',
  '19550000-0000-0000-0000-000000000001',
  'Private test course','private','[]'::jsonb,7,63.4,10.4);

do $$ begin
  if has_function_privilege(
    'anon',
    'public.search_shared_route_library(text,text,integer,double precision,double precision,integer,boolean,double precision,double precision)',
    'execute'
  ) then raise exception 'Public route catalogue RPC is callable anonymously'; end if;
  if (
    select pg_get_function_result(
      'public.search_shared_route_library(text,text,integer,double precision,double precision,integer,boolean,double precision,double precision)'::regprocedure
    )
  ) ilike '%coordinates%'
  then raise exception 'Catalogue leaks full GPS geometry'; end if;
end $$;

-- B follows A. One-way is not friendship.
insert into public.profile_follows(follower_id,following_id) values
 ('19550000-0000-0000-0000-000000000002',
  '19550000-0000-0000-0000-000000000001');
set local role authenticated;
set local request.jwt.claim.sub='19550000-0000-0000-0000-000000000002';
do $$ begin
  if not exists(
    select 1 from public.search_shared_route_library()
    where id='19550000-0000-0000-0000-000000000011'
  ) then raise exception 'Public route missing from library'; end if;
  if exists(
    select 1 from public.search_shared_route_library()
    where id in ('19550000-0000-0000-0000-000000000012',
                 '19550000-0000-0000-0000-000000000013')
  ) then raise exception 'One-way follower saw friends/private route'; end if;
  if exists(
    select 1 from public.search_shared_route_library(p_friends_only=>true)
    where id in ('19550000-0000-0000-0000-000000000011',
                 '19550000-0000-0000-0000-000000000012')
  ) then raise exception 'One-way follower saw friend-filtered route'; end if;
end $$;
reset role;

-- A follows B back. Public AND friends-only routes now qualify.
insert into public.profile_follows(follower_id,following_id) values
 ('19550000-0000-0000-0000-000000000001',
  '19550000-0000-0000-0000-000000000002');
set local role authenticated;
set local request.jwt.claim.sub='19550000-0000-0000-0000-000000000002';
do $$ begin
  if not exists(
    select 1 from public.search_shared_route_library()
    where id='19550000-0000-0000-0000-000000000012'
      and visibility='friends'
  ) then raise exception 'Mutual friend cannot see shared route'; end if;
  if (
    select count(*) from public.search_shared_route_library(p_friends_only=>true)
    where id in ('19550000-0000-0000-0000-000000000011',
                 '19550000-0000-0000-0000-000000000012')
  ) <> 2 then raise exception 'Friend filter does not include both accessible types'; end if;
  if exists(
    select 1 from public.search_shared_route_library()
    where id='19550000-0000-0000-0000-000000000013'
  ) then raise exception 'Private route leaked to mutual friend'; end if;
end $$;

-- User C never followed A, and must never see a friends route.
set local request.jwt.claim.sub='19550000-0000-0000-0000-000000000003';
do $$ begin
  if exists(
    select 1 from public.search_shared_route_library()
    where id in ('19550000-0000-0000-0000-000000000012',
                 '19550000-0000-0000-0000-000000000013')
  ) then raise exception 'Unrelated user saw restricted route'; end if;
end $$;
reset role;

-- Friendship revoked: friends-only discovery must disappear immediately.
delete from public.profile_follows
where follower_id='19550000-0000-0000-0000-000000000001'
  and following_id='19550000-0000-0000-0000-000000000002';
set local role authenticated;
set local request.jwt.claim.sub='19550000-0000-0000-0000-000000000002';
do $$ begin
  if exists(
    select 1 from public.search_shared_route_library()
    where id='19550000-0000-0000-0000-000000000012'
  ) then raise exception 'Revoked friendship still discovers private route'; end if;
end $$;
reset role;

select 'Public and mutual-friend route library checks passed' as result;
rollback;
