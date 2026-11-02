-- Open join, request join, privacy, and capacity tests; fixture changes rollback.
begin;
insert into auth.users(id) values
 ('16500000-0000-0000-0000-000000000001'),
 ('16500000-0000-0000-0000-000000000002'),
 ('16500000-0000-0000-0000-000000000003'),
 ('16500000-0000-0000-0000-000000000004');
insert into public.train_together_posts
 (id,creator_id,creator_display_name,title,workout_kind,scheduled_start,
  broad_area,status,join_policy,max_guests)
values
 ('16500000-0000-0000-0000-000000000011',
  '16500000-0000-0000-0000-000000000001',
  'Test host','Open enrollment test','running',now()+interval '1 day',
  'Test area','open','open',2),
 ('16500000-0000-0000-0000-000000000012',
  '16500000-0000-0000-0000-000000000001',
  'Test host','Request enrollment test','running',now()+interval '1 day',
  'Test area','open','request',2);

set local role authenticated;
set local request.jwt.claim.sub='16500000-0000-0000-0000-000000000002';
select public.join_train_together_open(
 '16500000-0000-0000-0000-000000000011'
) as first_join_session;
do $$ declare v_session uuid; begin
 select social_workout_session_id into v_session
 from public.train_together_posts
 where id='16500000-0000-0000-0000-000000000011';
 if v_session is null
    or (select count(*) from public.social_workout_participants
        where session_id=v_session and state in ('creator','accepted')) <> 2
    or not exists (select 1 from public.train_together_requests
      where post_id='16500000-0000-0000-0000-000000000011'
        and requester_id=auth.uid() and state='accepted')
 then raise exception 'Open join did not create the expected session'; end if;
 if public.join_train_together_open(
      '16500000-0000-0000-0000-000000000011'
    ) is distinct from v_session
    or (select accepted_guests from public.train_together_posts
        where id='16500000-0000-0000-0000-000000000011') <> 1
 then raise exception 'Repeated open join was not idempotent'; end if;
end $$;
select public.request_train_together_join(
 '16500000-0000-0000-0000-000000000012', 'Please include me'
) as pending_join_request;

set local request.jwt.claim.sub='16500000-0000-0000-0000-000000000001';
select public.respond_train_together_request(
 (select id from public.train_together_requests
  where post_id='16500000-0000-0000-0000-000000000012'
    and requester_id='16500000-0000-0000-0000-000000000002'),
 'accept'
) as approved_session;
do $$ begin
 if (select accepted_guests from public.train_together_posts
     where id='16500000-0000-0000-0000-000000000012') <> 1
    or not exists (select 1 from public.train_together_requests
        where post_id='16500000-0000-0000-0000-000000000012'
          and state='accepted')
 then raise exception 'Creator-approved request failed'; end if;
end $$;

set local request.jwt.claim.sub='16500000-0000-0000-0000-000000000003';
select public.join_train_together_open(
 '16500000-0000-0000-0000-000000000011'
) as second_join_session;
do $$ begin
 if (select accepted_guests from public.train_together_posts
     where id='16500000-0000-0000-0000-000000000011') <> 2
    or (select status from public.train_together_posts
        where id='16500000-0000-0000-0000-000000000011') <> 'full'
 then raise exception 'Full capacity not enforced'; end if;
end $$;

set local request.jwt.claim.sub='16500000-0000-0000-0000-000000000004';
do $$ declare unexpected_success boolean := false; begin
 begin
  perform public.join_train_together_open(
   '16500000-0000-0000-0000-000000000011'
  );
  unexpected_success := true;
 exception when raise_exception then
  if SQLERRM not like '%not available%' then raise; end if;
 end;
 if unexpected_success then raise exception 'Full session admitted another user'; end if;
end $$;

-- No independent authenticated INSERT can bypass the existing creator RLS.
do $$ declare unexpected_success boolean := false; begin
 begin
  insert into public.social_workout_participants
   (id,session_id,user_id,invited_by,state,display_name_snapshot,invited_at)
  select gen_random_uuid(),p.social_workout_session_id,
         '16500000-0000-0000-0000-000000000004',
         p.creator_id,'accepted','Forged participant',now()
  from public.train_together_posts p
  where p.id='16500000-0000-0000-0000-000000000011';
  unexpected_success := true;
 exception when others then
  null;
 end;
 if unexpected_success then
  raise exception 'Unauthorized participant INSERT was allowed';
 end if;
end $$;
reset role;
select 'Train Together open/request enrollment regressions passed' as result;
rollback;
