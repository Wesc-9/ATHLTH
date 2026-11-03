-- Existing, accepted players only; removed or declined athletes
-- cannot influence the vote count or a random tie after roster changes.
create or replace function public.athlth_tournament_finalize_exercises(
 p_tournament uuid
) returns uuid[] language plpgsql security definer set search_path='' as $$
declare
 v_t public.athlth_tournaments%rowtype;
 v_ids uuid[];
 v_user uuid:=auth.uid();
 v_index integer:=0;
 v_id uuid;
begin
 if v_user is null then raise exception 'Sign in required'; end if;
 select * into v_t from public.athlth_tournaments
    where id=p_tournament for update;
 if not found or v_t.owner_id<>v_user or v_t.status<>'inviting' then
    raise exception 'Only the organizer can finalize the invitation lobby';
 end if;
 if v_t.exercise_selection_finalized_at is not null then
    select array_agg(id order by selected_position) into v_ids
    from public.athlth_tournament_exercise_candidates
    where tournament_id=p_tournament and selected_position is not null;
    return coalesce(v_ids,array[]::uuid[]);
 end if;
 if v_t.exercise_mode='vote' and
    clock_timestamp()<v_t.votes_close_at then
    raise exception 'Wait until the ballot closes; abstentions are permitted';
 end if;
 if v_t.exercise_mode<>'open' and
    (select count(*) from public.athlth_tournament_exercise_candidates
       where tournament_id=p_tournament)<v_t.exercise_count then
    raise exception 'Not enough exercise candidates for this tournament';
 end if;
 for v_id in
   select c.id from public.athlth_tournament_exercise_candidates c
   left join (
     select candidate_id,count(*) as votes
     from public.athlth_tournament_exercise_votes ballot_votes
     join public.athlth_tournament_entries valid
       on valid.tournament_id=ballot_votes.tournament_id
      and valid.user_id=ballot_votes.voter_id
      and valid.response='accepted' and valid.removed_at is null
     where ballot_votes.tournament_id=p_tournament group by ballot_votes.candidate_id
   ) ballot on ballot.candidate_id=c.id
   where c.tournament_id=p_tournament
   order by case when v_t.exercise_mode='vote' then coalesce(ballot.votes,0)
                 else 0 end desc,
            case when v_t.exercise_mode='vote' then c.tie_break_key
                 else null end asc,
            c.created_at,c.id
   limit case when v_t.exercise_mode='open' then 500
              else v_t.exercise_count end
 loop
    v_index:=v_index+1;
    update public.athlth_tournament_exercise_candidates
      set selected_position=v_index where id=v_id;
 end loop;
 if v_index<1 then raise exception 'Add at least one exercise before finalizing'; end if;
 update public.athlth_tournaments
   set exercise_selection_finalized_at=now(),
       exercise_count=case when v_t.exercise_mode='open'
                           then v_index else v_t.exercise_count end
 where id=p_tournament;
 insert into public.athlth_tournament_audit(
     tournament_id,actor_id,event,info
 ) values(p_tournament,v_user,'exercises_finalized',
   jsonb_build_object('mode',v_t.exercise_mode,'selected',v_index,
                      'tie_break','stored_random_uuid'));
 select array_agg(id order by selected_position) into v_ids
 from public.athlth_tournament_exercise_candidates
 where tournament_id=p_tournament and selected_position is not null;
 return coalesce(v_ids,array[]::uuid[]);
end;
$$;


create or replace function private.athlth_tournament_close_due_ballots()
returns integer language plpgsql security definer set search_path='' as $$
declare
 v_t record;
 v_candidate uuid;
 v_position integer;
 v_processed integer:=0;
begin
 for v_t in
   select t.id,t.exercise_count
   from public.athlth_tournaments t
   where t.status='inviting' and t.exercise_mode='vote'
     and t.exercise_selection_finalized_at is null
     and t.votes_close_at<=clock_timestamp()
     and (select count(*) from public.athlth_tournament_exercise_candidates c
          where c.tournament_id=t.id)>=t.exercise_count
   for update of t skip locked
 loop
   v_position:=0;
   for v_candidate in
     select c.id
     from public.athlth_tournament_exercise_candidates c
     left join (
       select candidate_id,count(*) as votes
       from public.athlth_tournament_exercise_votes ballot_votes
       join public.athlth_tournament_entries valid
         on valid.tournament_id=ballot_votes.tournament_id
        and valid.user_id=ballot_votes.voter_id
        and valid.response='accepted' and valid.removed_at is null
       where ballot_votes.tournament_id=v_t.id group by ballot_votes.candidate_id
     ) totals on totals.candidate_id=c.id
     where c.tournament_id=v_t.id
     order by coalesce(totals.votes,0) desc,c.tie_break_key,c.id
     limit v_t.exercise_count
   loop
     v_position:=v_position+1;
     update public.athlth_tournament_exercise_candidates
       set selected_position=v_position where id=v_candidate;
   end loop;
   update public.athlth_tournaments
      set exercise_selection_finalized_at=clock_timestamp()
      where id=v_t.id;
   insert into public.athlth_tournament_audit(tournament_id,event,info)
    values(v_t.id,'ballot_auto_finalized',
     jsonb_build_object('selected',v_position,'ties','stored_random_uuid'));
   v_processed:=v_processed+1;
 end loop;
 return v_processed;
end;
$$;

revoke all on function public.athlth_tournament_finalize_exercises(uuid)
 from public,anon;
grant execute on function public.athlth_tournament_finalize_exercises(uuid)
 to authenticated;
revoke all on function private.athlth_tournament_close_due_ballots()
 from public,anon,authenticated;
