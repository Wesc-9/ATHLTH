-- Regression: the same points function serves shared and fixture formats.
do $test$
declare a uuid:='00000000-0000-0000-0000-000000000001'; b uuid:='00000000-0000-0000-0000-000000000002';
 e uuid:='00000000-0000-0000-0000-000000000003'; scores jsonb; actual jsonb;
begin
 scores:=jsonb_build_object(a::text,1200,b::text,1300);
 select jsonb_object_agg(p.user_id,p.points) into actual from private.athlth_exercise_points('{"scoringMode":"ranking"}','distance',e,scores,2) p;
 if actual<>jsonb_build_object(a::text,2,b::text,1) then raise exception 'Ranking incorrect'; end if;
 select jsonb_object_agg(p.user_id,p.points) into actual from private.athlth_exercise_points(jsonb_build_object('scoringMode','target','pointsPerExercise',3,'scoringGoals',jsonb_build_object(e::text,1250),'exerciseWeights',jsonb_build_object(e::text,2)),'distance',e,scores,2) p;
 if actual<>jsonb_build_object(a::text,6,b::text,0) then raise exception 'Goal scoring incorrect'; end if;
 select jsonb_object_agg(p.user_id,p.points) into actual from private.athlth_exercise_points(jsonb_build_object('scoringMode','winner','handicapPercentages',jsonb_build_object(b::text,10)),'distance',e,scores,2) p;
 if actual<>jsonb_build_object(a::text,0,b::text,1) then raise exception 'Time handicap incorrect'; end if;
 select jsonb_object_agg(p.user_id,p.points) into actual from private.athlth_exercise_points('{"scoringMode":"winner"}','repetitions',e,jsonb_build_object(a::text,10,b::text,20),2) p;
 if actual<>jsonb_build_object(a::text,0,b::text,1) then raise exception 'Strength scoring incorrect'; end if;
 select jsonb_object_agg(p.user_id,p.points) into actual from private.athlth_exercise_points('{"scoringMode":"winner"}','repetitions',e,jsonb_build_object(a::text,20,b::text,20),2) p;
 if actual<>jsonb_build_object(a::text,1,b::text,1) then raise exception 'Ties must share points'; end if;
 if has_function_privilege('anon','public.athlth_tournament_submit_measured_exercise(uuid,numeric,text)','EXECUTE')
 or has_function_privilege('authenticated','private.athlth_exercise_points(jsonb,text,uuid,jsonb,integer)','EXECUTE') then raise exception 'Scoring permissions unsafe'; end if;
end;$test$;
