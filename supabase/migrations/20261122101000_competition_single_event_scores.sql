create table if not exists public.athlth_tournament_single_event_results (
 tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 reported_score numeric(15,3) not null check(reported_score>=0 and reported_score<=100000000),
 reported_laps integer check(reported_laps between 0 and 500),
 evidence_note text not null check(length(btrim(evidence_note)) between 3 and 500),
 source_workout_id uuid,
 review_status text not null default 'submitted'
     check(review_status in ('submitted','approved','rejected')),
 submitted_at timestamptz not null default now(),
 reviewed_at timestamptz,
 reviewed_by uuid references auth.users(id),
 primary key(tournament_id,user_id)
);
alter table public.athlth_tournament_single_event_results enable row level security;
revoke all on public.athlth_tournament_single_event_results from public,anon,authenticated;
grant select on public.athlth_tournament_single_event_results to authenticated;
drop policy if exists single_event_result_private on public.athlth_tournament_single_event_results;
create policy single_event_result_private on public.athlth_tournament_single_event_results
for select to authenticated using(
 user_id=(select auth.uid()) or exists(
 select 1 from public.athlth_tournaments t
 where t.id=tournament_id and t.owner_id=(select auth.uid())
));

create or replace function public.athlth_tournament_single_event_submit(
 p_tournament uuid,p_score numeric,p_laps integer,p_evidence text,p_source_workout uuid default null)
returns void language plpgsql security definer set search_path='' as $fn$
declare t public.athlth_tournaments%rowtype; actor uuid:=auth.uid();
begin
 if actor is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament for update;
 if not found or not t.single_event_mode or t.status<>'active'
   or t.race_signal_at is null or clock_timestamp()<t.race_signal_at then
   raise exception 'The competition has not started'; end if;
 if not exists(select 1 from public.athlth_tournament_entries e
    where e.tournament_id=t.id and e.user_id=actor
      and e.response='accepted' and e.is_ready and e.removed_at is null) then
   raise exception 'You are not a ready participant'; end if;
 if p_score is null or p_score not between 0 and 100000000
   or length(btrim(coalesce(p_evidence,''))) not between 3 and 500
   or (p_laps is not null and p_laps not between 0 and 500) then
   raise exception 'Provide a valid result and evidence'; end if;
 if (t.race_rules->>'discipline')='laps' and
    p_laps is distinct from (t.race_rules->>'lapCount')::integer then
    raise exception 'A completed entry must include the required laps'; end if;
 if p_source_workout is not null and not exists(
   select 1 from public.social_challenge_attempts a
   where a.user_id=actor and a.source_workout_id=p_source_workout
    and a.verification='athlth' and a.is_eligible
    and a.started_at>=t.race_signal_at and a.ended_at<=clock_timestamp()
 ) then raise exception 'Workout is not verified for this start'; end if;
 -- Do not accept an unverified time-based sprint result. Health recording
 -- origin is not yet available in this table, so Watch-only requires a
 -- separately verified capture pipeline before such results can be approved.
 if (t.race_rules->>'discipline')='sprint' and p_source_workout is null then
   raise exception 'A verified ATHLTH workout is required for sprint'; end if;
 if (t.race_rules->>'recordingDevice')='apple_watch' then
   raise exception 'Apple Watch source attestation is not available yet'; end if;
 insert into public.athlth_tournament_single_event_results(
   tournament_id,user_id,reported_score,reported_laps,evidence_note,
   source_workout_id,review_status,submitted_at,reviewed_at,reviewed_by
 ) values(t.id,actor,p_score,p_laps,btrim(p_evidence),p_source_workout,
      'submitted',clock_timestamp(),null,null)
 on conflict(tournament_id,user_id)
 do update set reported_score=excluded.reported_score,
    reported_laps=excluded.reported_laps,evidence_note=excluded.evidence_note,
    source_workout_id=excluded.source_workout_id,review_status='submitted',
    submitted_at=excluded.submitted_at,reviewed_at=null,reviewed_by=null
 where public.athlth_tournament_single_event_results.review_status<>'approved';
 if not found then raise exception 'Approved results cannot be changed'; end if;
end;$fn$;

create or replace function public.athlth_tournament_single_event_review(
 p_tournament uuid,p_athlete uuid,p_approve boolean)
returns void language plpgsql security definer set search_path='' as $fn$
declare t public.athlth_tournaments%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament for update;
 if not found or not t.single_event_mode or t.status<>'active'
    or t.owner_id<>auth.uid() then
    raise exception 'Only the event organizer may review results'; end if;
 update public.athlth_tournament_single_event_results r
 set review_status=case when p_approve then 'approved' else 'rejected' end,
     reviewed_at=clock_timestamp(),reviewed_by=auth.uid()
 where r.tournament_id=t.id and r.user_id=p_athlete
   and r.review_status='submitted';
 if not found then raise exception 'No pending result'; end if;
 if not exists(
     select 1 from public.athlth_tournament_entries e
     where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null
       and not exists(select 1 from public.athlth_tournament_single_event_results r
         where r.tournament_id=t.id and r.user_id=e.user_id
           and r.review_status='approved')
 ) then
   update public.athlth_tournaments set status='completed',
       completed_at=clock_timestamp() where id=t.id;
   insert into public.athlth_tournament_audit(tournament_id,actor_id,event)
   values(t.id,auth.uid(),'single_event_completed');
 end if;
end;$fn$;

create or replace function public.athlth_tournament_single_event_status(
 p_tournament uuid)
returns table(user_id uuid,progress text,score numeric,rank bigint)
language plpgsql stable security definer set search_path='' as $fn$
declare t public.athlth_tournaments%rowtype; all_done boolean;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament;
 if not found or not t.single_event_mode or
    not private.athlth_tournament_can_view(t.id) then
     raise exception 'Competition not accessible'; end if;
 select not exists(select 1 from public.athlth_tournament_entries e
   where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null
     and not exists(select 1 from public.athlth_tournament_single_event_results r
       where r.tournament_id=t.id and r.user_id=e.user_id
         and r.review_status='approved'))
 into all_done;
 return query
 with scores as (
  select e.user_id,e.response,e.is_ready,r.review_status,r.reported_score,
    case when t.race_rules->>'discipline'='sprint' and
                   t.race_rules->>'sprintTarget' is distinct from 'duration'
                 or t.race_rules->>'discipline'='distance'
                 or t.race_rules->>'discipline'='laps'
         then true else false end as lower_wins
  from public.athlth_tournament_entries e
  left join public.athlth_tournament_single_event_results r
   on r.tournament_id=e.tournament_id and r.user_id=e.user_id
  where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null
 ), ranked as (
 select x.user_id,
    case when x.review_status='approved' then 'finished'
         when x.review_status='submitted' then 'awaiting_review'
         when x.review_status='rejected' then 'rejected'
         when not x.is_ready then 'not_ready' else 'waiting' end::text as p,
    x.reported_score,
    rank() over (order by
      (case when x.lower_wins then x.reported_score end) asc nulls last,
      (case when not x.lower_wins then x.reported_score end) desc nulls last
    ) as pos
  from scores x)
 select r.user_id,r.p,
  case when all_done or r.user_id=auth.uid() or t.owner_id=auth.uid()
    then r.reported_score else null end,
  case when all_done then r.pos else null end
 from ranked r order by r.pos;
end;$fn$;
revoke all on function public.athlth_tournament_single_event_submit(uuid,numeric,integer,text,uuid) from public,anon;
grant execute on function public.athlth_tournament_single_event_submit(uuid,numeric,integer,text,uuid) to authenticated;
revoke all on function public.athlth_tournament_single_event_review(uuid,uuid,boolean) from public,anon;
grant execute on function public.athlth_tournament_single_event_review(uuid,uuid,boolean) to authenticated;
revoke all on function public.athlth_tournament_single_event_status(uuid) from public,anon;
grant execute on function public.athlth_tournament_single_event_status(uuid) to authenticated;