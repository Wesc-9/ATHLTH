-- Local/CI only; every fixture is rolled back.
begin;
insert into auth.users(id) values
 ('10000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000002'),
 ('10000000-0000-0000-0000-000000000003');
insert into public.profile_follows(follower_id,following_id) values
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002');
update public.profile_social_settings set profile_visibility='public' where user_id in
 ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002');
do $$ begin
 if has_function_privilege('anon','public.manage_athlete_coach(text,uuid,uuid,boolean,boolean,boolean)','execute')
 or has_table_privilege('authenticated','public.athlete_coach_connections','update')
 or has_table_privilege('authenticated','public.athlete_coach_snapshots','insert')
 then raise exception 'Consent or snapshot bypass privileges exposed'; end if;
end $$;
set local role authenticated;
set local request.jwt.claim.sub='10000000-0000-0000-0000-000000000001';
select public.manage_athlete_coach('request',p_coach=>'10000000-0000-0000-0000-000000000002',p_workouts=>true);
do $$ declare c uuid; begin
 select id into c from public.athlete_coach_connections;
 begin
  perform public.manage_athlete_coach('accept',c);
  raise exception 'Athlete accepted own coach invitation';
 exception when insufficient_privilege then null; end;
 begin
  perform public.publish_athlete_coach_snapshot(c,'private plan','[]',50);
  raise exception 'Pending coach received data';
 exception when insufficient_privilege then null; end;
end $$;
set local request.jwt.claim.sub='10000000-0000-0000-0000-000000000002';
do $$ declare c uuid; begin
 select id into c from public.athlete_coach_connections;
 perform public.manage_athlete_coach('accept',c);
 begin
  perform public.manage_athlete_coach('scopes',c,p_plan=>true);
  raise exception 'Coach escalated own consent';
 exception when insufficient_privilege then null; end;
 begin
  perform public.publish_athlete_coach_snapshot(c,'forged','[]',50);
  raise exception 'Coach forged athlete snapshot';
 exception when insufficient_privilege then null; end;
end $$;
set local request.jwt.claim.sub='10000000-0000-0000-0000-000000000001';
do $$ declare c uuid; begin
 select id into c from public.athlete_coach_connections;
 perform public.publish_athlete_coach_snapshot(c,'private plan','[{"title":"Run","activity":"Running","date":"2026-10-04","minutes":"30","gps":"secret","cycle":"secret"}]',50);
 if exists(select 1 from public.athlete_coach_snapshots where plan_text is not null or readiness_score is not null
  or workouts::text like '%secret%') then raise exception 'Unconsented fields escaped snapshot filtering'; end if;
 begin
  insert into public.athlete_coach_feedback(connection_id,author_id,kind,body) values(c,auth.uid(),'proposal','Forge coach proposal');
  raise exception 'Athlete forged coach-only proposal';
 exception when insufficient_privilege then null; end;
end $$;
set local request.jwt.claim.sub='10000000-0000-0000-0000-000000000003';
do $$ begin
 if exists(select 1 from public.athlete_coach_connections) or exists(select 1 from public.athlete_coach_snapshots)
 then raise exception 'Stranger can read coach data'; end if;
end $$;
set local request.jwt.claim.sub='10000000-0000-0000-0000-000000000002';
do $$ declare c uuid; begin
 select id into c from public.athlete_coach_connections;
 if not exists(select 1 from public.athlete_coach_snapshots where workouts->0->>'title'='Run') then raise exception 'Consented coach cannot see snapshot'; end if;
 insert into public.athlete_coach_feedback(connection_id,author_id,kind,body) values(c,auth.uid(),'proposal','Reduce Friday duration');
end $$;
set local request.jwt.claim.sub='10000000-0000-0000-0000-000000000001';
do $$ declare c uuid; begin
 select id into c from public.athlete_coach_connections;
 perform public.manage_athlete_coach('scopes',c,p_workouts=>false,p_plan=>true);
 if exists(select 1 from public.athlete_coach_snapshots) then raise exception 'Scope change retained old data'; end if;
 perform public.publish_athlete_coach_snapshot(c,'Consented plan','[]',50);
 perform public.manage_athlete_coach('revoke',c);
end $$;
set local request.jwt.claim.sub='10000000-0000-0000-0000-000000000002';
do $$ begin
 if exists(select 1 from public.athlete_coach_snapshots) or exists(select 1 from public.athlete_coach_feedback)
 then raise exception 'Revoked coach can still access data'; end if;
end $$;
set local request.jwt.claim.sub='10000000-0000-0000-0000-000000000001';
insert into public.training_partner_availability(id,user_id,starts_at,ends_at,area,sport,level,enabled) values
 ('20000000-0000-0000-0000-000000000001',auth.uid(),now()+interval '1 hour',now()+interval '2 hours','oslo','running','intermediate',true),
 ('20000000-0000-0000-0000-000000000002',auth.uid(),now()+interval '1 hour',now()+interval '2 hours','oslo','running','intermediate',false);
set local request.jwt.claim.sub='10000000-0000-0000-0000-000000000003';
do $$ begin
 if (select count(*) from public.training_partner_availability) <> 1 then raise exception 'Unpublished availability leaked or published slot hidden'; end if;
 begin
  insert into public.training_partner_availability(user_id,starts_at,ends_at,area,sport,level,enabled)
  values('10000000-0000-0000-0000-000000000001',now()+interval '1 hour',now()+interval '2 hours','oslo','running','intermediate',true);
  raise exception 'Forged availability accepted';
 exception when insufficient_privilege then null; end;
 delete from public.training_partner_availability;
end $$;
set local request.jwt.claim.sub='10000000-0000-0000-0000-000000000001';
do $$ begin
 if (select count(*) from public.training_partner_availability) <> 2 then raise exception 'Stranger deleted availability'; end if;
end $$;
reset role;
insert into public.user_blocks(blocker_id,blocked_id) values('10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001');
set local role authenticated;
set local request.jwt.claim.sub='10000000-0000-0000-0000-000000000003';
do $$ begin
 if exists(select 1 from public.training_partner_availability) then raise exception 'Blocked availability visible'; end if;
end $$;
reset role;
rollback;
