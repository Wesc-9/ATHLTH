-- All fixtures and state changes are rolled back, including when run remotely.
begin;
insert into auth.users(id) values
 ('16300000-0000-0000-0000-000000000001'),
 ('16300000-0000-0000-0000-000000000002'),
 ('16300000-0000-0000-0000-000000000003');
insert into public.train_together_posts
 (id,creator_id,creator_display_name,title,workout_kind,scheduled_start,broad_area,status)
values
 ('16300000-0000-0000-0000-000000000011','16300000-0000-0000-0000-000000000001','RLS owner','Upcoming run','running',now()+interval '1 day','Test area','open'),
 ('16300000-0000-0000-0000-000000000012','16300000-0000-0000-0000-000000000001','RLS owner','Historical run','running',now()+interval '1 day','Test area','completed'),
 ('16300000-0000-0000-0000-000000000013','16300000-0000-0000-0000-000000000001','RLS owner','Unrelated run','running',now()+interval '1 day','Test area','cancelled');
insert into public.train_together_requests(post_id,requester_id,requester_display_name)
values ('16300000-0000-0000-0000-000000000012','16300000-0000-0000-0000-000000000002','RLS guest');
insert into public.train_together_post_meetups(post_id,creator_id,meeting_name)
values ('16300000-0000-0000-0000-000000000012','16300000-0000-0000-0000-000000000001','Private test meetup');

do $$ begin
 if has_function_privilege('anon','private.has_train_together_request(uuid)','execute') then
   raise exception 'Anonymous helper execution is exposed';
 end if;
end $$;
set local role authenticated;
set local request.jwt.claim.sub='16300000-0000-0000-0000-000000000001';
do $$ begin
 if (select count(*) from public.train_together_posts where creator_id=auth.uid()) <> 3
 or (select count(*) from public.train_together_requests where post_id='16300000-0000-0000-0000-000000000012') <> 1
 or (select count(*) from public.train_together_post_meetups where post_id='16300000-0000-0000-0000-000000000012') <> 1
 then raise exception 'Owner lost access'; end if;
end $$;
set local request.jwt.claim.sub='16300000-0000-0000-0000-000000000002';
do $$ begin
 if (select count(*) from public.train_together_posts where creator_id='16300000-0000-0000-0000-000000000001') <> 2
 then raise exception 'Requester post visibility incorrect'; end if;
 if not private.has_train_together_request('16300000-0000-0000-0000-000000000012')
 or private.has_train_together_request('16300000-0000-0000-0000-000000000013')
 then raise exception 'Request lookup matched the wrong post'; end if;
 if exists(select 1 from public.train_together_post_meetups where post_id='16300000-0000-0000-0000-000000000012')
 then raise exception 'Pending requester saw private meetup'; end if;
 update public.train_together_posts set title='Forged title' where id='16300000-0000-0000-0000-000000000011';
 if found then raise exception 'Non-owner edited a post'; end if;
end $$;
set local request.jwt.claim.sub='16300000-0000-0000-0000-000000000003';
do $$ begin
 if (select count(*) from public.train_together_posts where creator_id='16300000-0000-0000-0000-000000000001') <> 1
 or exists(select 1 from public.train_together_requests where post_id='16300000-0000-0000-0000-000000000012')
 or exists(select 1 from public.train_together_post_meetups where post_id='16300000-0000-0000-0000-000000000012')
 then raise exception 'Unrelated user saw restricted data'; end if;
end $$;
reset role;
update public.train_together_requests set state='accepted'
 where post_id='16300000-0000-0000-0000-000000000012';
insert into public.user_blocks(blocker_id,blocked_id)
values ('16300000-0000-0000-0000-000000000001','16300000-0000-0000-0000-000000000003');
set local role authenticated;
set local request.jwt.claim.sub='16300000-0000-0000-0000-000000000002';
do $$ begin
 if not exists(select 1 from public.train_together_post_meetups where post_id='16300000-0000-0000-0000-000000000012')
 then raise exception 'Accepted guest lost meetup access'; end if;
end $$;
set local request.jwt.claim.sub='16300000-0000-0000-0000-000000000003';
do $$ begin
 if exists(select 1 from public.train_together_posts where creator_id='16300000-0000-0000-0000-000000000001')
 then raise exception 'Blocked user saw discoverable post'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
 begin
  perform 1 from public.train_together_posts;
  raise exception 'Anonymous post access allowed';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'Train Together RLS regression checks passed' as result;
rollback;
