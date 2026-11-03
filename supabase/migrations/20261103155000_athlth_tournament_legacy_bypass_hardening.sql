-- Do not let older create RPCs bypass the mandatory sport/rule contract.
-- The approved create-with-rules RPC invokes them as the trusted owner.
revoke execute on function public.athlth_tournament_create(
 text,text,uuid,uuid,integer,integer,uuid[],text[]) from authenticated;
revoke execute on function public.athlth_tournament_create_configured(
 text,text,uuid,uuid,integer,integer,uuid[],text[],text,integer,
 timestamptz,timestamptz,boolean) from authenticated;
-- Old strength catalog uses training categories, not sport categories.
-- Only explicit strength categories may be selected as strength exercises.
create or replace function public.athlth_tournament_suggest_exercise(
 p_tournament uuid,p_exercise uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_t public.athlth_tournaments%rowtype;
 v_candidate uuid;
 v_user uuid:=auth.uid();
begin
 if v_user is null then raise exception 'Sign in required'; end if;
 select * into v_t from public.athlth_tournaments where id=p_tournament for update;
 if not found or v_t.status<>'inviting' or
   v_t.exercise_selection_finalized_at is not null then
   raise exception 'Exercise suggestions are closed';
 end if;
 if v_t.rules_confirmed_at is null then
    raise exception 'Approve tournament rules before starting or entering the exercises';
 end if;
 if (v_t.exercise_mode='owner' and v_user<>v_t.owner_id) or
    (v_t.exercise_mode<>'owner' and not private.athlth_tournament_is_accepted(p_tournament)) then
   raise exception 'Cannot suggest exercises in this tournament';
 end if;
 if v_t.exercise_mode='vote' and clock_timestamp()>=v_t.proposals_close_at then
   raise exception 'Exercise nomination period has ended';
 end if;
 if not ('strength'=any(v_t.allowed_activities)) then
    raise exception 'Strength exercises are not permitted in this tournament';
 end if;
 if not exists(
   select 1 from public.exercise_catalog
   where id=p_exercise and is_published
     and category in ('strength','core','strength-endurance','carry','conditioning')
 ) then
   raise exception 'Select a published strength exercise; other sport templates are separate';
 end if;
 if (select count(*) from public.athlth_tournament_exercise_candidates
      where tournament_id=p_tournament)>=500 then
   raise exception 'Tournament suggestion limit reached';
 end if;
 insert into public.athlth_tournament_exercise_candidates(
      tournament_id,exercise_id,suggested_by
 ) values(p_tournament,p_exercise,v_user)
 on conflict (tournament_id,exercise_id) do nothing returning id into v_candidate;
 if v_candidate is null then
    select id into v_candidate from public.athlth_tournament_exercise_candidates
     where tournament_id=p_tournament and exercise_id=p_exercise;
 end if;
 return v_candidate;
end;
$$;


revoke all on function public.athlth_tournament_suggest_exercise(uuid,uuid)
 from public,anon;
grant execute on function public.athlth_tournament_suggest_exercise(uuid,uuid)
 to authenticated;
