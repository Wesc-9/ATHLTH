begin;
insert into auth.users(id) values ('30020000-0000-0000-0000-000000000001'),('30020000-0000-0000-0000-000000000002'),('30020000-0000-0000-0000-000000000003');
insert into public.social_workout_draft_lobbies(source_workout_id,owner_id,partner_id,edit_mode,participation_mode,workout_snapshot) values
('30020000-0000-0000-0000-000000000011','30020000-0000-0000-0000-000000000001','30020000-0000-0000-0000-000000000002','collaborative','physical','{}'),
('30020000-0000-0000-0000-000000000012','30020000-0000-0000-0000-000000000001','30020000-0000-0000-0000-000000000003','collaborative','remote','{}');
set local role authenticated;
set local request.jwt.claim.sub='30020000-0000-0000-0000-000000000001';
insert into public.social_workout_room_messages(id,source_workout_id,sender_id,body) values
('30020000-0000-0000-0000-000000000021','30020000-0000-0000-0000-000000000011',auth.uid(),'Room one'),
('30020000-0000-0000-0000-000000000022','30020000-0000-0000-0000-000000000012',auth.uid(),'Room two');
set local request.jwt.claim.sub='30020000-0000-0000-0000-000000000002';
do $$ begin
 if (select count(*) from public.social_workout_room_messages where source_workout_id in ('30020000-0000-0000-0000-000000000011','30020000-0000-0000-0000-000000000012')) <> 1 then raise exception 'Wrong room visibility'; end if;
 begin
 insert into public.social_workout_room_messages(id,source_workout_id,sender_id,body) values(gen_random_uuid(),'30020000-0000-0000-0000-000000000012',auth.uid(),'Wrong room');
 raise exception 'Cross-room insert allowed';
 exception when insufficient_privilege then null; end;
 begin
 insert into public.social_workout_room_messages(id,source_workout_id,sender_id,body) values(gen_random_uuid(),'30020000-0000-0000-0000-000000000011','30020000-0000-0000-0000-000000000001','Forged');
 raise exception 'Sender spoof allowed';
 exception when insufficient_privilege then null; end;
 end $$;
insert into public.social_workout_room_messages(id,source_workout_id,sender_id,body) values(gen_random_uuid(),'30020000-0000-0000-0000-000000000011',auth.uid(),'Partner reply');
set local request.jwt.claim.sub='30020000-0000-0000-0000-000000000001';
do $$ begin if (select count(*) from public.social_workout_room_messages where source_workout_id='30020000-0000-0000-0000-000000000011') <> 2 then raise exception 'Reply not visible'; end if; end $$;
reset role;
update public.social_workout_draft_lobbies set cancelled_at=now(), owner_approved_revision=null, partner_approved_revision=null where source_workout_id='30020000-0000-0000-0000-000000000011';
set local role authenticated;
set local request.jwt.claim.sub='30020000-0000-0000-0000-000000000002';
do $$ begin
 begin
 insert into public.social_workout_room_messages(id,source_workout_id,sender_id,body) values(gen_random_uuid(),'30020000-0000-0000-0000-000000000011',auth.uid(),'After withdrawal');
 raise exception 'Cancelled room accepts messages';
 exception when insufficient_privilege then null; end;
 end $$;
reset role;
rollback;
select 'Private room chat access checks passed' as result;
