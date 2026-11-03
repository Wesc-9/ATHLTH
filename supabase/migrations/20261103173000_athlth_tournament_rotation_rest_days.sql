-- Arena exercise rotation and real rest-day calendar, without changing
-- any fixtures already created under earlier rules.
alter table public.athlth_tournaments
 add column if not exists competition_timezone text not null default 'Europe/Oslo';

create or replace function private.athlth_tournament_next_allowed(
 p_date timestamptz, p_rest integer[], p_tz text
) returns timestamptz language plpgsql stable set search_path='' as $$
declare
 v_value timestamptz:=p_date;
 v_i integer;
begin
 for v_i in 1..14 loop
   if not (extract(isodow from v_value at time zone p_tz)::integer
      = any(p_rest)) then return v_value; end if;
   v_value:=v_value+interval '1 day';
 end loop;
 raise exception 'Tournament has no available training day';
end;
$$;

create or replace function private.athlth_tournament_last_open(
 p_start timestamptz, p_count integer,
 p_cadence integer, p_rest integer[], p_tz text
) returns timestamptz language plpgsql stable set search_path='' as $$
declare
 v_date timestamptz:=p_start;
 v_i integer;
begin
 v_date:=private.athlth_tournament_next_allowed(v_date,p_rest,p_tz);
 for v_i in 2..greatest(1,p_count) loop
    v_date:=private.athlth_tournament_next_allowed(
      v_date+p_cadence*interval '1 day',p_rest,p_tz
    );
 end loop;
 return v_date;
end;
$$;

create or replace function private.athlth_tournament_set_match_dates()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 v_t public.athlth_tournaments%rowtype;
 v_practices integer;
 v_count integer;
 v_base timestamptz;
 v_i integer;
begin
 select * into v_t from public.athlth_tournaments
 where id=new.tournament_id;
 if not found then raise exception 'Tournament not found'; end if;
 select count(*) into v_practices from public.athlth_tournament_practice
 where tournament_id=new.tournament_id;
 if new.phase='warmup' then
    new.scheduled_at:=coalesce(new.scheduled_at,
       clock_timestamp()+(new.round_number-1)*v_t.round_days*interval '1 day');
    new.deadline_at:=coalesce(new.deadline_at,
       new.scheduled_at+v_t.round_days*interval '1 day');
    return new;
 end if;

 v_count:=case when v_t.rotation_mode='all'
        then greatest(1,v_t.exercise_count) else 1 end;
 if new.phase='playoff' or
    (new.phase='cup' and new.round_number>1) then
    v_base:=clock_timestamp();
 else
    v_base:=clock_timestamp()+v_practices*v_t.round_days*interval '1 day';
    -- Every official round receives its own sequence. The next round
    -- starts only after the previous round's last exercise window.
    for v_i in 2..new.round_number loop
       v_base:=private.athlth_tournament_last_open(
          v_base,v_count,v_t.cadence_days,v_t.rest_weekdays,
          v_t.competition_timezone
       )+v_t.completion_hours*interval '1 hour';
    end loop;
 end if;
 new.scheduled_at:=coalesce(new.scheduled_at,
   private.athlth_tournament_next_allowed(
     v_base,v_t.rest_weekdays,v_t.competition_timezone
   ));
 new.deadline_at:=coalesce(new.deadline_at,
   private.athlth_tournament_last_open(
     new.scheduled_at,v_count,v_t.cadence_days,v_t.rest_weekdays,
     v_t.competition_timezone
   )+v_t.completion_hours*interval '1 hour'
 );
 return new;
end;
$$;

create or replace function private.athlth_tournament_initialize_exercise_deadlines()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 v_candidate record;
 v_t public.athlth_tournaments%rowtype;
 v_count integer;
 v_choice integer;
 v_cycle integer;
 v_start timestamptz;
 v_position integer:=0;
begin
 if new.phase='warmup' or new.away_id is null then return new; end if;
 select * into v_t from public.athlth_tournaments
 where id=new.tournament_id;
 select count(*) into v_count
 from public.athlth_tournament_exercise_candidates
 where tournament_id=new.tournament_id and selected_position is not null;
 if v_count=0 then return new; end if;

 v_choice:=(new.round_number-1)%v_count+1;
 v_cycle:=(new.round_number-1)/v_count;
 v_start:=private.athlth_tournament_next_allowed(
   new.scheduled_at,v_t.rest_weekdays,v_t.competition_timezone
 );

 for v_candidate in
   with ranked as (
     select c.id,c.selected_position,
       row_number() over(
         order by
           case when v_t.rotation_mode='shuffle'
              then md5(new.tournament_id::text||':'||v_cycle::text||':'||c.id::text)
              else lpad(c.selected_position::text,6,'0') end,
           c.id
       ) rn
     from public.athlth_tournament_exercise_candidates c
     where c.tournament_id=new.tournament_id and c.selected_position is not null
   )
   select id,selected_position from ranked
   where v_t.rotation_mode='all'
      or rn=v_choice
   order by case when v_t.rotation_mode='all' then selected_position else 1 end
 loop
    v_position:=v_position+1;
    insert into public.athlth_tournament_match_exercises(
       tournament_id,match_id,candidate_id,position,scheduled_at,deadline_at
    ) values(
       new.tournament_id,new.id,v_candidate.id,v_position,v_start,
       v_start+v_t.completion_hours*interval '1 hour'
    );
    v_start:=private.athlth_tournament_next_allowed(
       v_start+v_t.cadence_days*interval '1 day',
       v_t.rest_weekdays,v_t.competition_timezone
    );
 end loop;
 return new;
end;
$$;

revoke all on function private.athlth_tournament_next_allowed(
 timestamptz,integer[],text),private.athlth_tournament_last_open(
 timestamptz,integer,integer,integer[],text) from public,anon,authenticated;
revoke all on function private.athlth_tournament_set_match_dates(),
 private.athlth_tournament_initialize_exercise_deadlines()
 from public,anon,authenticated;
