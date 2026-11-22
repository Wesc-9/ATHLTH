-- Participant progress deliberately contains no scores or evidence notes.
-- Live activity is included only where the viewing athlete already has
-- permission to view the underlying live workout.
create or replace function public.athlth_tournament_participant_progress(
    p_tournament uuid
) returns table(user_id uuid,phase text,last_activity_at timestamptz)
language plpgsql stable security definer set search_path='' as $fn$
begin
    if auth.uid() is null or not exists(
        select 1 from public.athlth_tournament_entries e
        where e.tournament_id=p_tournament and e.user_id=auth.uid()
          and e.response in ('accepted','invited') and e.removed_at is null
    ) then
        raise exception 'You are not a member of this competition';
    end if;
    return query
    select e.user_id,
        case
          when e.response='invited' then 'invited'
          when e.is_ready is not true then 'not_ready'
          when t.status='completed' then 'finished'
          when t.status<>'active' then 'waiting'
          when exists (
              select 1 from public.athlth_tournament_matches m
              where m.tournament_id=t.id and m.status='confirmed'
              and e.user_id in (m.home_id,m.away_id)
              and m.round_number=(select min(x.round_number)
                  from public.athlth_tournament_matches x
                  where x.tournament_id=t.id and x.status<>'confirmed'
                    and x.phase<>'warmup' and x.away_id is not null)
          ) then 'finished'
          when exists (
              select 1 from public.live_workout_sessions l
              where l.owner_id=e.user_id and l.status in ('active','paused')
                and l.started_at>=t.started_at
                and l.started_at>clock_timestamp()-interval '6 hours'
                and l.activity=any(t.allowed_activities)
                and private.can_view_live_workout(l.id)
          ) then 'training'
          when exists (
              select 1 from public.athlth_tournament_exercise_completions c
              join public.athlth_tournament_match_exercises s
                   on s.id=c.match_exercise_id
              join public.athlth_tournament_matches m on m.id=s.match_id
              where m.tournament_id=t.id and c.user_id=e.user_id
                and c.review_status in ('submitted','approved')
          ) then 'reported'
          else 'waiting'
        end::text,
        (select max(c.submitted_at)
         from public.athlth_tournament_exercise_completions c
         join public.athlth_tournament_match_exercises s
             on s.id=c.match_exercise_id
         where s.tournament_id=t.id and c.user_id=e.user_id)::timestamptz
    from public.athlth_tournament_entries e
    join public.athlth_tournaments t on t.id=e.tournament_id
    where t.id=p_tournament and e.removed_at is null
      and e.response in ('invited','accepted')
    order by e.seed,e.user_id;
end;
$fn$;
revoke all on function public.athlth_tournament_participant_progress(uuid)
from public,anon;
grant execute on function public.athlth_tournament_participant_progress(uuid)
to authenticated;