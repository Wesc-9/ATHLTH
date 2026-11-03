-- Group-managed competitions vote on the entire exercise and scoring
-- contract. Voters never silently inherit the organizer's advanced options.
create or replace function public.athlth_tournament_propose_full_rules(
 p_tournament uuid,p_allowed_activities text[],
 p_cadence_days integer,p_completion_hours integer,
 p_rotation_mode text,p_rest_weekdays integer[],
 p_proof_mode text,p_win_points integer,p_draw_points integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_id uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_rotation_mode not in ('all','sequence','shuffle')
    or p_proof_mode not in ('opponent','verified')
    or p_win_points not between 1 and 10
    or p_draw_points not between 0 and least(3,p_win_points-1)
    or p_rest_weekdays is null
    or not (p_rest_weekdays <@ array[1,2,3,4,5,6,7]::integer[])
    or cardinality(p_rest_weekdays)>=7
    or (select count(distinct x) from unnest(p_rest_weekdays) x)
          <>cardinality(p_rest_weekdays) then
   raise exception 'Invalid proposed tournament rules';
 end if;
 v_id:=public.athlth_tournament_propose_rules(
    p_tournament,p_allowed_activities,p_cadence_days,p_completion_hours
 );
 update public.athlth_tournament_rule_proposals
 set rotation_mode=p_rotation_mode, rest_weekdays=p_rest_weekdays,
     proof_mode=p_proof_mode,win_points=p_win_points,draw_points=p_draw_points
 where id=v_id;
 return v_id;
end;
$$;
revoke all on function public.athlth_tournament_propose_full_rules(
 uuid,text[],integer,integer,text,integer[],text,integer,integer
) from public,anon;
grant execute on function public.athlth_tournament_propose_full_rules(
 uuid,text[],integer,integer,text,integer[],text,integer,integer
) to authenticated;
revoke execute on function public.athlth_tournament_propose_rules(
 uuid,text[],integer,integer) from authenticated;
