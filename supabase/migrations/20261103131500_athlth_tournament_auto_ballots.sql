-- Closing a voting ballot must not depend on organizer presence.
-- Each candidate's random tie_break_key was stored when nominated.
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
       from public.athlth_tournament_exercise_votes
       where tournament_id=v_t.id group by candidate_id
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
revoke all on function private.athlth_tournament_close_due_ballots()
 from public,anon,authenticated;

-- Insufficient nominations should never generate surprise exercises.
-- Give the organizer an audited option to reopen nominations. Clear old
-- votes so late-added candidates participate in a fresh, fair ballot.
create or replace function public.athlth_tournament_extend_ballot(
 p_tournament uuid
) returns void language plpgsql security definer set search_path='' as $$
declare
 v_t public.athlth_tournaments%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into v_t from public.athlth_tournaments
    where id=p_tournament for update;
 if not found or v_t.owner_id<>auth.uid() or
    v_t.status<>'inviting' or v_t.exercise_mode<>'vote' or
    v_t.exercise_selection_finalized_at is not null or
    v_t.votes_close_at>clock_timestamp() then
    raise exception 'Only an expired, unfinalized ballot can be extended';
 end if;
 delete from public.athlth_tournament_exercise_votes
  where tournament_id=p_tournament;
 update public.athlth_tournaments
    set proposals_close_at=clock_timestamp()+interval '24 hours',
        votes_close_at=clock_timestamp()+interval '48 hours'
  where id=p_tournament;
 insert into public.athlth_tournament_audit(
     tournament_id,actor_id,event,info
 ) values(p_tournament,auth.uid(),'ballot_reopened',
   jsonb_build_object('previous_close',v_t.votes_close_at,
                      'votes_reset',true));
end;
$$;
revoke all on function public.athlth_tournament_extend_ballot(uuid)
 from public,anon;
grant execute on function public.athlth_tournament_extend_ballot(uuid)
 to authenticated;

do $$
begin
 if not exists (select 1 from cron.job where jobname='athlth-tournament-vote-finalization') then
   perform cron.schedule(
     'athlth-tournament-vote-finalization',
     '*/2 * * * *',
     'select private.athlth_tournament_close_due_ballots();'
   );
 end if;
end;
$$;
