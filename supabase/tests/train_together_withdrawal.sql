begin;

insert into auth.users(id) values ('30010000-0000-0000-0000-000000000001'),('30010000-0000-0000-0000-000000000002'),('30010000-0000-0000-0000-000000000003');

insert into public.direct_conversations(id,user_a,user_b,request_status,requested_by) values ('30010000-0000-0000-0000-000000000010','30010000-0000-0000-0000-000000000001','30010000-0000-0000-0000-000000000002','accepted','30010000-0000-0000-0000-000000000001');

insert into public.social_workout_draft_lobbies(source_workout_id,owner_id,partner_id,edit_mode,participation_mode,workout_snapshot,owner_approved_revision,partner_approved_revision) values ('30010000-0000-0000-0000-000000000011','30010000-0000-0000-0000-000000000001','30010000-0000-0000-0000-000000000002','collaborative','physical','{"id":"30010000-0000-0000-0000-000000000011","kind":"running"}',1,1);

insert into public.social_workout_sessions(id,creator_id,title,workout_kind,status,started_at,invite_payload) values ('30010000-0000-0000-0000-000000000012','30010000-0000-0000-0000-000000000001','Withdrawal test','running','active',now(),'{"workout":{"id":"30010000-0000-0000-0000-000000000011","kind":"running"},"participationMode":"physical"}');

set local role authenticated;

set local request.jwt.claim.sub='30010000-0000-0000-0000-000000000001';

insert into public.direct_messages(conversation_id,sender_id,recipient_id,attachment_kind,attachment_title,attachment_payload,share_version,source_object_id,source_owner_id) values ('30010000-0000-0000-0000-000000000010','30010000-0000-0000-0000-000000000001','30010000-0000-0000-0000-000000000002','workout','Workout invitation','{"id":"30010000-0000-0000-0000-000000000011","kind":"running"}',2,'30010000-0000-0000-0000-000000000011','30010000-0000-0000-0000-000000000001');

set local request.jwt.claim.sub='30010000-0000-0000-0000-000000000002';

do $$ begin begin insert into public.direct_messages(conversation_id,sender_id,recipient_id,attachment_kind,attachment_title,attachment_payload,share_version,source_object_id,source_owner_id) values ('30010000-0000-0000-0000-000000000010','30010000-0000-0000-0000-000000000002','30010000-0000-0000-0000-000000000001','workout','Forged withdrawal','{"kind":"cancelled","sourceWorkoutID":"30010000-0000-0000-0000-000000000011","organizerID":"30010000-0000-0000-0000-000000000001"}',6,'30010000-0000-0000-0000-000000000011','30010000-0000-0000-0000-000000000001');
raise exception 'TEST FAILED: forged withdrawal'; exception when raise_exception then if SQLERRM <> 'Only the original organizer can withdraw an invitation' then raise; end if; end; end $$;

set local request.jwt.claim.sub='30010000-0000-0000-0000-000000000001';

insert into public.direct_messages(conversation_id,sender_id,recipient_id,attachment_kind,attachment_title,attachment_payload,share_version,source_object_id,source_owner_id) values ('30010000-0000-0000-0000-000000000010','30010000-0000-0000-0000-000000000001','30010000-0000-0000-0000-000000000002','workout','Withdrawn','{"kind":"cancelled","sourceWorkoutID":"30010000-0000-0000-0000-000000000011","organizerID":"30010000-0000-0000-0000-000000000001"}',6,'30010000-0000-0000-0000-000000000011','30010000-0000-0000-0000-000000000001');

insert into public.direct_messages(conversation_id,sender_id,recipient_id,attachment_kind,attachment_title,attachment_payload,share_version,source_object_id,source_owner_id) values ('30010000-0000-0000-0000-000000000010','30010000-0000-0000-0000-000000000001','30010000-0000-0000-0000-000000000002','workout','Retry withdrawal','{"kind":"cancelled","sourceWorkoutID":"30010000-0000-0000-0000-000000000011","organizerID":"30010000-0000-0000-0000-000000000001"}',6,'30010000-0000-0000-0000-000000000011','30010000-0000-0000-0000-000000000001');

do $$ begin if (select count(*) from public.direct_messages where conversation_id='30010000-0000-0000-0000-000000000010' and share_version=6) <> 1 then raise exception 'TEST FAILED: duplicate cancellation'; end if; end $$;

do $$ begin if not exists (select 1 from public.social_workout_draft_lobbies where source_workout_id='30010000-0000-0000-0000-000000000011' and cancelled_at is not null and owner_approved_revision is null and partner_approved_revision is null) then raise exception 'TEST FAILED: draft or approvals still active'; end if; end $$;

do $$ begin if not exists (select 1 from public.social_workout_sessions where id='30010000-0000-0000-0000-000000000012' and status='cancelled' and workout_phase='cancelled') then raise exception 'TEST FAILED: ready lobby still active'; end if; end $$;

do $$ begin begin insert into public.social_workout_sessions(id,creator_id,title,workout_kind,status,started_at,invite_payload) values ('30010000-0000-0000-0000-000000000013','30010000-0000-0000-0000-000000000001','Withdrawal test','running','active',now(),'{"workout":{"id":"30010000-0000-0000-0000-000000000011","kind":"running"},"participationMode":"physical"}');
raise exception 'TEST FAILED: reopened lobby'; exception when raise_exception then if SQLERRM <> 'Train Together invitation was withdrawn' then raise; end if; end; end $$;

set local request.jwt.claim.sub='30010000-0000-0000-0000-000000000002';

do $$ begin if not exists(select 1 from public.direct_messages where conversation_id='30010000-0000-0000-0000-000000000010' and share_version=6) then raise exception 'TEST FAILED: guest cannot see withdrawal'; end if; end $$;

do $$ begin begin insert into public.direct_messages(conversation_id,sender_id,recipient_id,attachment_kind,attachment_title,attachment_payload,share_version,source_object_id,source_owner_id) values ('30010000-0000-0000-0000-000000000010','30010000-0000-0000-0000-000000000002','30010000-0000-0000-0000-000000000001','workout','Late acceptance','{"sourceWorkoutID":"30010000-0000-0000-0000-000000000011","decision":"accepted"}',3,'30010000-0000-0000-0000-000000000011','30010000-0000-0000-0000-000000000001');
raise exception 'TEST FAILED: late acceptance'; exception when raise_exception then if SQLERRM <> 'Train Together invitation was withdrawn' then raise; end if; end; end $$;

do $$ begin begin perform public.approve_social_workout_draft('30010000-0000-0000-0000-000000000011',1);
raise exception 'TEST FAILED: late approval'; exception when raise_exception then if SQLERRM <> 'Train Together invitation was withdrawn' then raise; end if; end; end $$;

do $$ begin begin perform public.update_social_workout_draft('30010000-0000-0000-0000-000000000011',1,'{"id":"30010000-0000-0000-0000-000000000011","kind":"running","title":"Stale edit"}');
raise exception 'TEST FAILED: late edit'; exception when raise_exception then if SQLERRM <> 'Train Together invitation was withdrawn' then raise; end if; end; end $$;

set local request.jwt.claim.sub='30010000-0000-0000-0000-000000000003';

do $$ begin if exists(select 1 from public.social_workout_draft_lobbies where source_workout_id='30010000-0000-0000-0000-000000000011') or exists(select 1 from public.direct_messages where conversation_id='30010000-0000-0000-0000-000000000010') then raise exception 'TEST FAILED: outsider visibility'; end if; end $$;

reset role;

rollback;

select 'Train Together withdrawal database regression checks passed (all fixtures rolled back)' as result;
