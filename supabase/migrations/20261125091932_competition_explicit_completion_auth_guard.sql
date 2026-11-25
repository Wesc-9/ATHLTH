CREATE OR REPLACE FUNCTION public.athlth_tournament_complete_exercise(p_match_exercise uuid, p_evidence_note text, p_source_workout uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if exists(select 1 from public.athlth_tournament_match_exercises s join public.athlth_tournaments t on t.id=s.tournament_id
   where s.id=p_match_exercise and t.race_rules ? 'scoringMode') then
   raise exception 'Submit a measured result with the updated ATHLTH app';
 end if;
 perform private.athlth_tournament_record_completion(p_match_exercise,p_evidence_note,p_source_workout);
end;$function$
;
