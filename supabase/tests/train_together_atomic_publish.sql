-- Transactional Train Together publication: no partial writes and no
-- unauthorised meetup visibility. All fixtures are rolled back.
begin;
insert into auth.users(id) values
 ('16400000-0000-0000-0000-000000000001'),
 ('16400000-0000-0000-0000-000000000002');

do $$ begin
  if has_function_privilege(
    'anon', 'public.publish_train_together_post(jsonb,jsonb)', 'execute'
  ) then raise exception 'Anonymous publication must be forbidden'; end if;
end $$;

set local role authenticated;
set local request.jwt.claim.sub = '16400000-0000-0000-0000-000000000001';

select public.publish_train_together_post(
  jsonb_build_object(
    'id', '16400000-0000-0000-0000-000000000011',
    'creator_id', '16400000-0000-0000-0000-000000000001',
    'creator_display_name', 'Atomic test athlete',
    'title', 'Atomic publication test',
    'workout_kind', 'running',
    'scheduled_start', now() + interval '1 day',
    'broad_area', 'Test area',
    'max_guests', 3,
    'join_policy', 'open',
    'participation_mode', 'physical'
  ),
  jsonb_build_object(
    'post_id', '16400000-0000-0000-0000-000000000011',
    'creator_id', '16400000-0000-0000-0000-000000000001',
    'meeting_name', 'Private meeting place'
  )
);
do $$ begin
  if not exists (
    select 1 from public.train_together_posts
    where id='16400000-0000-0000-0000-000000000011' and join_policy='open'
  ) or not exists (
    select 1 from public.train_together_post_meetups
    where post_id='16400000-0000-0000-0000-000000000011'
  ) then raise exception 'Atomic publication omitted a row'; end if;
end $$;

-- The second insert must fail, rolling back the first insert too.
do $$ begin
  begin
    perform public.publish_train_together_post(
      jsonb_build_object(
        'id', '16400000-0000-0000-0000-000000000012',
        'creator_id', '16400000-0000-0000-0000-000000000001',
        'creator_display_name', 'Atomic test athlete',
        'title', 'Invalid private meetup',
        'workout_kind', 'running',
        'scheduled_start', now() + interval '1 day',
        'broad_area', 'Test area',
        'max_guests', 3
      ),
      jsonb_build_object(
        'post_id', '16400000-0000-0000-0000-000000000012',
        'creator_id', '16400000-0000-0000-0000-000000000001',
        'meeting_latitude', 200
      )
    );
    raise exception 'Expected invalid latitude failure';
  exception
    when check_violation then null;
  end;
  if exists (
    select 1 from public.train_together_posts
    where id='16400000-0000-0000-0000-000000000012'
  ) then raise exception 'Failed meetup left an orphaned workout'; end if;
end $$;

set local request.jwt.claim.sub = '16400000-0000-0000-0000-000000000002';
do $$ begin
  if exists (
    select 1 from public.train_together_post_meetups
    where post_id='16400000-0000-0000-0000-000000000011'
  ) then raise exception 'Uninvited guest could read private location'; end if;
  begin
    perform public.publish_train_together_post(
      jsonb_build_object(
        'id', '16400000-0000-0000-0000-000000000013',
        'creator_id', '16400000-0000-0000-0000-000000000001',
        'creator_display_name', 'Forged identity',
        'title', 'Spoof attempt',
        'workout_kind', 'running',
        'scheduled_start', now() + interval '1 day',
        'broad_area', 'Test area',
        'max_guests', 1
      ),
      null
    );
    raise exception 'Expected creator mismatch';
  exception
    when raise_exception then
      if SQLERRM = 'Expected creator mismatch' then raise; end if;
  end;
end $$;
reset role;
select 'Atomic Train Together publication tests passed' as result;
rollback;
