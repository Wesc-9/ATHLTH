-- Run only against a disposable local Supabase database after migrations.
begin;
insert into auth.users(id) values
  ('00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000002');
insert into public.profile_social_settings(user_id)
values ('00000000-0000-0000-0000-000000000001') on conflict do nothing;
do $$ begin
  if exists (select 1 from public.profile_social_settings
    where user_id = '00000000-0000-0000-0000-000000000001'
    and (share_recent_activity or share_performance_stats or share_workout_totals
      or recent_activity_visibility <> 'private' or performance_stats_visibility <> 'private'))
  then raise exception 'Health information defaults are not private'; end if;
  if (select public from storage.buckets where id = 'workout-media')
  then raise exception 'Workout bucket is public'; end if;
  if has_function_privilege('authenticated', 'public.account_storage_objects_for_deletion(uuid,integer)', 'execute')
    or has_function_privilege('anon', 'public.account_storage_objects_for_deletion(uuid,integer)', 'execute')
  then raise exception 'Account inventory exposed to clients'; end if;
end $$;

insert into storage.objects(bucket_id,name,owner_id) values
  ('workout-media','00000000-0000-0000-0000-000000000001/workout/photo.jpg','00000000-0000-0000-0000-000000000001'),
  ('workout-media','00000000-0000-0000-0000-000000000001/pending.jpg',null),
  ('profile-gear','shared/gear.jpg','00000000-0000-0000-0000-000000000001'),
  ('profile-gear','other/gear.jpg','00000000-0000-0000-0000-000000000002');
insert into public.workout_media(user_id,workout_id,image_url,storage_path)
values ('00000000-0000-0000-0000-000000000001',gen_random_uuid(),'https://example.test/locator',
 '00000000-0000-0000-0000-000000000001/workout/photo.jpg');

set local role service_role;
do $$ begin
  if (select count(*) from public.account_storage_objects_for_deletion('00000000-0000-0000-0000-000000000001',100)) <> 3
  then raise exception 'Inventory missed owned files or included another owner'; end if;
  if (select count(*) from public.account_storage_objects_for_deletion('00000000-0000-0000-0000-000000000001',1)) <> 1
  then raise exception 'Inventory limit not respected'; end if;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
do $$ begin
  if (select count(*) from storage.objects where bucket_id='workout-media') <> 2
  then raise exception 'Owner cannot read uploads'; end if;
  if public.is_username_available('bad.name') or public.is_username_available('åbc')
    or public.is_username_available(repeat('a',21)) or public.is_username_available('ab')
    or not public.is_username_available('valid_name')
  then raise exception 'Username availability disagrees with profile constraint'; end if;
end $$;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
do $$ begin
  if exists (select 1 from storage.objects where bucket_id='workout-media')
  then raise exception 'Private workout images leaked to another user'; end if;
end $$;
reset role;
update public.profile_social_settings set recent_activity_visibility='public',share_recent_activity=true
where user_id='00000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$ begin
  if (select count(*) from storage.objects where bucket_id='workout-media') <> 1
  then raise exception 'Publicly shared photo unavailable or pending photo leaked'; end if;
end $$;
reset role;
-- Covers share a bucket with photos but use event/challenge audiences.
insert into public.community_events(id,creator_id,title,activity_type,visibility,starts_at,meeting_name)
values
 ('00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000001','Public event','running','public',now()+interval '1 day','Test meeting'),
 ('00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000001','Private event','running','private',now()+interval '1 day','Test meeting');
insert into public.social_challenges(id,creator_id,title,sport,status,rules,visibility,starts_at)
values
 ('00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000001','Public challenge','running','upcoming','{}','public',now()+interval '1 day'),
 ('00000000-0000-0000-0000-000000000013','00000000-0000-0000-0000-000000000001','Private challenge','running','upcoming','{}','private',now()+interval '1 day');
insert into storage.objects(bucket_id,name)
values
 ('workout-media','00000000-0000-0000-0000-000000000001/event-covers/00000000-0000-0000-0000-000000000010.jpg'),
 ('workout-media','00000000-0000-0000-0000-000000000001/event-covers/00000000-0000-0000-0000-000000000011.jpg'),
 ('workout-media','00000000-0000-0000-0000-000000000001/challenge-covers/00000000-0000-0000-0000-000000000012.jpg'),
 ('workout-media','00000000-0000-0000-0000-000000000001/challenge-covers/00000000-0000-0000-0000-000000000013.jpg');
set local role authenticated;
do $$ begin
  if (select count(*) from storage.objects where bucket_id='workout-media' and name like '%-covers/%') <> 2
  then raise exception 'Cover image access does not respect content audiences'; end if;
end $$;
reset role;
-- Atomic, weighted user budget shared across endpoints.
do $$
declare result record;
begin
  if has_function_privilege('authenticated','public.consume_ai_request_budget(uuid,text)','execute')
  then raise exception 'Clients can consume arbitrary budgets'; end if;
  select * into result from public.consume_ai_request_budget('00000000-0000-0000-0000-000000000001','generate-training-program');
  if not result.allowed then raise exception 'First generation denied'; end if;
  select * into result from public.consume_ai_request_budget('00000000-0000-0000-0000-000000000001','generate-plan-adaptation');
  if not result.allowed then raise exception 'Second generation denied'; end if;
  select * into result from public.consume_ai_request_budget('00000000-0000-0000-0000-000000000001','workout-insight');
  if result.allowed or result.retry_after < 1 or result.retry_after > 60
  then raise exception 'Shared minute budget bypassed'; end if;
  select * into result from public.consume_ai_request_budget('00000000-0000-0000-0000-000000000002','recovery-sense');
  if not result.allowed then raise exception 'Another account budget affected'; end if;
  update private.ai_request_budgets set minute_start=now()-interval '2 minutes',day_units=100
  where user_id='00000000-0000-0000-0000-000000000001';
  select * into result from public.consume_ai_request_budget('00000000-0000-0000-0000-000000000001','recovery-sense');
  if result.allowed or result.retry_after < 1 or result.retry_after > 86400
  then raise exception 'Daily budget bypassed'; end if;
  update private.ai_request_budgets set day_start=now()-interval '2 days'
  where user_id='00000000-0000-0000-0000-000000000001';
  select * into result from public.consume_ai_request_budget('00000000-0000-0000-0000-000000000001','recovery-sense');
  if not result.allowed then raise exception 'New day budget not reset'; end if;
end $$;
rollback;
