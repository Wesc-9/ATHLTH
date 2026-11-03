-- A tournament match consists of the selected exercises. Every exercise
-- has its own deadline within the match window. Warmups never cause walkovers.
create table if not exists public.athlth_tournament_match_exercises (
 id uuid primary key default gen_random_uuid(),
 tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
 match_id uuid not null references public.athlth_tournament_matches(id) on delete cascade,
 candidate_id uuid not null references public.athlth_tournament_exercise_candidates(id),
 position smallint not null,
 deadline_at timestamptz not null,
 state text not null default 'pending'
   check(state in ('pending','completed','walkover','disputed')),
 winner_id uuid references public.profiles(id),
 resolved_at timestamptz,
 unique(match_id,candidate_id)
);
create index if not exists athlth_exercise_deadline_pending
 on public.athlth_tournament_match_exercises(deadline_at)
 where state='pending';

create table if not exists public.athlth_tournament_exercise_completions (
 match_exercise_id uuid not null
    references public.athlth_tournament_match_exercises(id) on delete cascade,
 user_id uuid not null references public.profiles(id),
 source_workout_id uuid,
 evidence_note text not null check(length(btrim(evidence_note)) between 3 and 500),
 submitted_at timestamptz not null default now(),
 primary key(match_exercise_id,user_id)
);

alter table public.athlth_tournament_match_exercises enable row level security;
alter table public.athlth_tournament_exercise_completions enable row level security;
create policy "match_exercise_visible_to_entrant"
 on public.athlth_tournament_match_exercises for select to authenticated
 using(private.athlth_tournament_is_entrant(tournament_id));
create policy "completion_visible_to_entrant"
 on public.athlth_tournament_exercise_completions for select to authenticated
 using(exists(select 1 from public.athlth_tournament_match_exercises m
   where m.id=match_exercise_id
     and private.athlth_tournament_is_entrant(m.tournament_id)));
revoke all on public.athlth_tournament_match_exercises,
 public.athlth_tournament_exercise_completions from public,anon,authenticated;
grant select on public.athlth_tournament_match_exercises,
 public.athlth_tournament_exercise_completions to authenticated;

create or replace function private.athlth_tournament_initialize_exercise_deadlines()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 v_exercise record;
 v_count integer;
begin
 if new.phase='warmup' or new.away_id is null then return new; end if;
 select count(*) into v_count
 from public.athlth_tournament_exercise_candidates
 where tournament_id=new.tournament_id and selected_position is not null;
 if v_count=0 then return new; end if;
 for v_exercise in
   select id,selected_position
   from public.athlth_tournament_exercise_candidates
   where tournament_id=new.tournament_id and selected_position is not null
   order by selected_position
 loop
   insert into public.athlth_tournament_match_exercises(
      tournament_id,match_id,candidate_id,position,deadline_at
   ) values (
      new.tournament_id,new.id,v_exercise.id,v_exercise.selected_position,
      coalesce(new.scheduled_at,now()) +
       (coalesce(new.deadline_at,now())-coalesce(new.scheduled_at,now()))
        * (v_exercise.selected_position::double precision/v_count)
   );
 end loop;
 return new;
end;
$$;
drop trigger if exists athlth_tournament_match_exercises_insert
 on public.athlth_tournament_matches;
create trigger athlth_tournament_match_exercises_insert
after insert on public.athlth_tournament_matches
for each row execute function private.athlth_tournament_initialize_exercise_deadlines();

create or replace function private.athlth_tournament_retime_exercises()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 v_count integer;
begin
 if new.deadline_at is not distinct from old.deadline_at then return new; end if;
 select count(*) into v_count from public.athlth_tournament_match_exercises
  where match_id=new.id;
 update public.athlth_tournament_match_exercises e
 set deadline_at=coalesce(new.scheduled_at,now()) +
     (new.deadline_at-coalesce(new.scheduled_at,now()))
     * (e.position::double precision/greatest(1,v_count))
 where e.match_id=new.id and e.state='pending';
 return new;
end;
$$;
drop trigger if exists athlth_tournament_match_exercises_retime
 on public.athlth_tournament_matches;
create trigger athlth_tournament_match_exercises_retime
after update of deadline_at on public.athlth_tournament_matches
for each row execute function private.athlth_tournament_retime_exercises();

create or replace function public.athlth_tournament_complete_exercise(
 p_match_exercise uuid,p_evidence_note text,p_source_workout uuid default null
) returns void language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();
 v_ex public.athlth_tournament_match_exercises%rowtype;
 v_match public.athlth_tournament_matches%rowtype;
 v_state text;
begin
 if v_user is null then raise exception 'Sign in required'; end if;
 select * into v_ex from public.athlth_tournament_match_exercises
 where id=p_match_exercise for update;
 if not found or v_ex.state<>'pending' or now()>v_ex.deadline_at then
   raise exception 'Exercise deadline has passed';
 end if;
 select * into v_match from public.athlth_tournament_matches
 where id=v_ex.match_id;
 select status into v_state from public.athlth_tournaments
 where id=v_ex.tournament_id;
 if v_state<>'active' or v_match.status='confirmed' or
    v_user not in (v_match.home_id,v_match.away_id) or
    not private.athlth_tournament_is_accepted(v_ex.tournament_id) then
   raise exception 'This exercise is not open to this athlete';
 end if;
 if v_match.scheduled_at>now() then
   raise exception 'Exercise has not started';
 end if;
 if p_evidence_note is null or
    length(btrim(p_evidence_note)) not between 3 and 500 then
   raise exception 'Provide a short description of the completed workout';
 end if;
 insert into public.athlth_tournament_exercise_completions(
    match_exercise_id,user_id,source_workout_id,evidence_note
 ) values(p_match_exercise,v_user,p_source_workout,btrim(p_evidence_note))
 on conflict(match_exercise_id,user_id) do nothing;
end;
$$;

-- This is intended for pg_cron. Only exercise completion captured before
-- its deadline counts. Missing a single exercise results in a match walkover
-- when the opponent has submitted completion evidence on time.
-- If neither athlete submitted, do NOT invent a winner: flag for a ruling.
create or replace function private.athlth_tournament_process_exercise_deadlines()
returns integer language plpgsql security definer set search_path='' as $$
declare
 v_slot record;
 v_match public.athlth_tournament_matches%rowtype;
 v_home boolean;
 v_away boolean;
 v_loser uuid;
 v_count integer:=0;
begin
 for v_slot in
   select e.id,e.match_id,e.tournament_id,e.deadline_at
   from public.athlth_tournament_match_exercises e
   join public.athlth_tournaments t on t.id=e.tournament_id
   where e.state='pending' and e.deadline_at<=clock_timestamp()
     and t.status='active'
   order by e.deadline_at,e.id
   for update of e skip locked
 loop
   select * into v_match from public.athlth_tournament_matches
    where id=v_slot.match_id for update;
   if not found or v_match.status='confirmed' then
     update public.athlth_tournament_match_exercises
       set state='completed',resolved_at=now() where id=v_slot.id;
     continue;
   end if;
   select exists(select 1 from public.athlth_tournament_exercise_completions
      where match_exercise_id=v_slot.id and user_id=v_match.home_id)
     into v_home;
   select exists(select 1 from public.athlth_tournament_exercise_completions
      where match_exercise_id=v_slot.id and user_id=v_match.away_id)
     into v_away;
   if v_home and v_away then
     update public.athlth_tournament_match_exercises
       set state='completed',resolved_at=now() where id=v_slot.id;
   elsif v_home<>v_away then
     v_loser:=case when v_home then v_match.away_id else v_match.home_id end;
     update public.athlth_tournament_match_exercises
       set state='walkover',winner_id=case when v_home
             then v_match.home_id else v_match.away_id end,
           resolved_at=now() where id=v_slot.id;
     update public.athlth_tournament_matches
       set status='confirmed',
           home_score=case when v_home then 1 else 0 end,
           away_score=case when v_away then 1 else 0 end,
           walkover_loser_id=v_loser,
           walkover_reason='exercise_deadline_missed',
           evidence_note='Walkover: missed exercise completion deadline',
           confirmed_at=now(),confirmed_by=null,proposed_by=null
       where id=v_match.id;
     insert into public.athlth_tournament_audit(tournament_id,event,info)
       values(v_slot.tournament_id,'exercise_walkover',
        jsonb_build_object('match',v_match.id,'exercise_slot',v_slot.id,
                           'winner',case when v_home then v_match.home_id
                                         else v_match.away_id end,
                           'loser',v_loser,'deadline',v_slot.deadline_at));
     perform private.athlth_tournament_advance(v_slot.tournament_id);
     v_count:=v_count+1;
   else
     -- Both absent: cannot arbitrarily decide an elimination winner.
     update public.athlth_tournament_match_exercises
       set state='disputed',resolved_at=now() where id=v_slot.id;
     update public.athlth_tournament_matches set status='disputed'
       where id=v_match.id and status='scheduled';
     insert into public.athlth_tournament_audit(tournament_id,event,info)
       values(v_slot.tournament_id,'both_missed_exercise',
        jsonb_build_object('match',v_match.id,'exercise_slot',v_slot.id));
   end if;
 end loop;
 return v_count;
end;
$$;
revoke all on function private.athlth_tournament_process_exercise_deadlines()
 from public,anon,authenticated;
revoke all on function private.athlth_tournament_retime_exercises(),
 private.athlth_tournament_initialize_exercise_deadlines()
 from public,anon,authenticated;
revoke all on function public.athlth_tournament_complete_exercise(uuid,text,uuid)
 from public,anon;
grant execute on function public.athlth_tournament_complete_exercise(uuid,text,uuid)
 to authenticated;
