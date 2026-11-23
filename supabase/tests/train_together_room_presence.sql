begin;
insert into auth.users(id) values ('30030000-0000-0000-0000-000000000001'),('30030000-0000-0000-0000-000000000002'),('30030000-0000-0000-0000-000000000003');
insert into public.profiles(id) values ('30030000-0000-0000-0000-000000000001'),('30030000-0000-0000-0000-000000000002'),('30030000-0000-0000-0000-000000000003') on conflict(id) do nothing;
insert into public.social_workout_draft_lobbies(source_workout_id,owner_id,partner_id,edit_mode,participation_mode,workout_snapshot) values
('30030000-0000-0000-0000-000000000011','30030000-0000-0000-0000-000000000001','30030000-0000-0000-0000-000000000002','collaborative','physical','{"id":"30030000-0000-0000-0000-000000000011","kind":"running","title":"Run"}');
set local role authenticated;
set local request.jwt.claim.sub='30030000-0000-0000-0000-000000000001';
select public.set_workout_room_presence('30030000-0000-0000-0000-000000000011','viewing');
select public.set_workout_room_presence('30030000-0000-0000-0000-000000000011','editing');
select public.update_social_workout_draft('30030000-0000-0000-0000-000000000011',1,'{"id":"30030000-0000-0000-0000-000000000011","kind":"running","title":"Revised"}');
insert into public.social_workout_room_messages(id,source_workout_id,sender_id,body) values(gen_random_uuid(),'30030000-0000-0000-0000-000000000011',auth.uid(),'Private test body'),(gen_random_uuid(),'30030000-0000-0000-0000-000000000011',auth.uid(),'Second private body');
set local request.jwt.claim.sub='30030000-0000-0000-0000-000000000002';
do $$ begin
 if not exists(select 1 from public.social_workout_room_presence where source_workout_id='30030000-0000-0000-0000-000000000011' and status='editing') then raise exception 'Presence missing'; end if;
 if not exists(select 1 from public.social_workout_room_history where source_workout_id='30030000-0000-0000-0000-000000000011' and revision=2 and changed_fields=array['title'] and actor_id='30030000-0000-0000-0000-000000000001') then raise exception 'History missing'; end if;
 if (select count(*) from public.social_inbox_events where entity_id='30030000-0000-0000-0000-000000000011' and entity_type='shared_workout_room' and recipient_id=auth.uid()) <> 2 then raise exception 'Notification deduplication failed'; end if;
 if exists(select 1 from public.social_inbox_events where entity_id='30030000-0000-0000-0000-000000000011' and message ilike '%private%body%') then raise exception 'Chat body exposed'; end if;
end $$;
set local request.jwt.claim.sub='30030000-0000-0000-0000-000000000003';
do $$ begin
 if exists(select 1 from public.social_workout_room_presence where source_workout_id='30030000-0000-0000-0000-000000000011') or exists(select 1 from public.social_workout_room_history where source_workout_id='30030000-0000-0000-0000-000000000011') then raise exception 'Room leaked'; end if;
 begin perform public.set_workout_room_presence('30030000-0000-0000-0000-000000000011','editing'); raise exception 'Foreign presence allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
select 'Presence, history, notification privacy and deduplication passed' as result;
