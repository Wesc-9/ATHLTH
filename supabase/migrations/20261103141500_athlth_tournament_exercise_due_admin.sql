-- Each chosen exercise has its own configurable cutoff. Organizers may
-- reschedule an unresolved exercise within its match window; every change is
-- audited. A confirmed result or recorded walkover is immutable.
create or replace function public.athlth_tournament_set_exercise_deadline(
 p_match_exercise uuid,p_deadline timestamptz
) returns void language plpgsql security definer set search_path='' as $$
declare
 v_actor uuid:=auth.uid();
 v_ex public.athlth_tournament_match_exercises%rowtype;
 v_match public.athlth_tournament_matches%rowtype;
 v_t public.athlth_tournaments%rowtype;
begin
 if v_actor is null then raise exception 'Sign in required'; end if;
 select * into v_ex from public.athlth_tournament_match_exercises
  where id=p_match_exercise for update;
 if not found or v_ex.state<>'pending' then
   raise exception 'Exercise deadline is no longer editable';
 end if;
 select * into v_match from public.athlth_tournament_matches
  where id=v_ex.match_id for update;
 select * into v_t from public.athlth_tournaments
  where id=v_ex.tournament_id for update;
 if v_t.owner_id<>v_actor or v_t.status<>'active' or
   v_match.status='confirmed' then
   raise exception 'Only organizer may edit an unresolved active exercise';
 end if;
 if p_deadline is null or p_deadline<now()+interval '1 minute' or
   p_deadline<coalesce(v_match.scheduled_at,now()) or
   p_deadline>v_match.deadline_at then
    raise exception 'Exercise deadline must be within the match window';
 end if;
 update public.athlth_tournament_match_exercises
   set deadline_at=p_deadline where id=p_match_exercise;
 insert into public.athlth_tournament_audit(
    tournament_id,actor_id,event,info
 ) values(v_t.id,v_actor,'exercise_deadline_updated',
   jsonb_build_object('exercise_slot',v_ex.id,
                      'previous',v_ex.deadline_at,
                      'new',p_deadline));
end;
$$;
revoke all on function public.athlth_tournament_set_exercise_deadline(
 uuid,timestamptz) from public,anon;
grant execute on function public.athlth_tournament_set_exercise_deadline(
 uuid,timestamptz) to authenticated;
