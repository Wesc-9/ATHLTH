create or replace function private.athlth_competition_slot_schedule()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare v_t public.athlth_tournaments%rowtype;
 v_match public.athlth_tournament_matches%rowtype;
 v_gap interval; v_start timestamptz;
begin
 select * into v_t from public.athlth_tournaments where id=new.tournament_id;
 if not found or not v_t.competition_settings_applied or new.position<1
 then return new; end if;
 select * into v_match from public.athlth_tournament_matches
 where id=new.match_id;
 if not found or v_match.phase='warmup' then return new; end if;
 if v_t.release_mode='everyone_finished' and new.position>1 then
   v_start:=timestamptz '2099-12-31 00:00:00+00';
 else
   v_gap:=case v_t.release_unit
     when 'minute' then make_interval(mins=>v_t.release_every)
     when 'hour' then make_interval(hours=>v_t.release_every)
     when 'day' then make_interval(days=>v_t.release_every)
     else make_interval(months=>v_t.release_every)
   end;
   v_start:=v_match.scheduled_at+(new.position-1)*v_gap;
 end if;
 update public.athlth_tournament_match_exercises
 set scheduled_at=v_start,
     deadline_at=v_start+v_t.completion_hours*interval '1 hour'
 where id=new.id;
 return new;
end;
$fn$;
drop trigger if exists athlth_competition_slot_schedule
on public.athlth_tournament_match_exercises;
create trigger athlth_competition_slot_schedule
after insert on public.athlth_tournament_match_exercises
for each row execute function private.athlth_competition_slot_schedule();
revoke all on function private.athlth_competition_slot_schedule()
from public,anon,authenticated;