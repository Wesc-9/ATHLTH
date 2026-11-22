revoke select on public.athlth_tournament_match_exercises from authenticated;
grant select(id,tournament_id,match_id,candidate_id,position,scheduled_at,deadline_at,state,resolved_at)
on public.athlth_tournament_match_exercises to authenticated;
create or replace function public.athlth_tournament_visible_match_exercises(p_matches uuid[])
returns table(id uuid,match_id uuid,candidate_id uuid,"position" smallint,
scheduled_at timestamptz,deadline_at timestamptz,state text,winner_id uuid)
language plpgsql stable security definer set search_path='' as $fn$
begin
 if auth.uid() is null or coalesce(array_length(p_matches,1),0)>200
 then raise exception 'Invalid exercise list'; end if;
 return query
 select s.id,s.match_id,s.candidate_id,s.position,
 s.scheduled_at,s.deadline_at,s.state,
 case when auth.uid()=t.owner_id or auth.uid() in (m.home_id,m.away_id)
  or t.format not in ('league','groups') or not t.competition_settings_applied
  or t.status='completed'
  or not exists(select 1 from public.athlth_tournament_matches x
    where x.tournament_id=t.id and x.phase=m.phase
      and x.round_number=m.round_number
      and x.group_index is not distinct from m.group_index
      and x.away_id is not null and x.status<>'confirmed')
 then s.winner_id else null end
 from public.athlth_tournament_match_exercises s
 join public.athlth_tournament_matches m on m.id=s.match_id
 join public.athlth_tournaments t on t.id=s.tournament_id
 where s.match_id=any(p_matches)
 and private.athlth_tournament_is_entrant(t.id)
 order by s.match_id,s.position;
end;
$fn$;
revoke all on function public.athlth_tournament_visible_match_exercises(uuid[])
from public,anon;
grant execute on function public.athlth_tournament_visible_match_exercises(uuid[])
to authenticated;
drop policy if exists completion_visible_to_entrant
on public.athlth_tournament_exercise_completions;
create policy completion_visible_to_competitors
on public.athlth_tournament_exercise_completions
for select to authenticated using (exists(
 select 1 from public.athlth_tournament_match_exercises s
 join public.athlth_tournament_matches m on m.id=s.match_id
 join public.athlth_tournaments t on t.id=s.tournament_id
 where s.id=match_exercise_id and private.athlth_tournament_is_entrant(t.id)
 and (not t.competition_settings_applied
  or (select auth.uid()) in (m.home_id,m.away_id,t.owner_id))
));
drop policy if exists tournament_audit_read on public.athlth_tournament_audit;
create policy tournament_audit_read_sealed
on public.athlth_tournament_audit
for select to authenticated using (
 private.athlth_tournament_can_view(tournament_id)
 and (not exists(select 1 from public.athlth_tournaments t
     where t.id=tournament_id and t.competition_settings_applied
       and t.status<>'completed')
    or exists(select 1 from public.athlth_tournaments t
       where t.id=tournament_id and t.owner_id=(select auth.uid())))
);