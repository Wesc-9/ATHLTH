create or replace function private.athlth_competition_start_gate()
returns trigger language plpgsql set search_path='' as $fn$
begin
 if old.status is distinct from new.status and new.status='active' and
    new.planned_starts_at is not null and
    clock_timestamp()<new.planned_starts_at then
    raise exception 'Competition cannot start before its planned date';
 end if;
 if old.rules_frozen_at is not null and
   (old.planned_starts_at is distinct from new.planned_starts_at or
    old.release_mode is distinct from new.release_mode or
    old.release_every is distinct from new.release_every or
    old.release_unit is distinct from new.release_unit or
    old.invitation_permission is distinct from new.invitation_permission or
    old.join_approval is distinct from new.join_approval or
    old.allowed_actions is distinct from new.allowed_actions or
    old.prohibited_actions is distinct from new.prohibited_actions or
    old.prize_first is distinct from new.prize_first or
    old.prize_second is distinct from new.prize_second or
    old.prize_third is distinct from new.prize_third or
    old.loser_consequence is distinct from new.loser_consequence)
 then raise exception 'Competition rules are locked'; end if;
 return new;
end;
$fn$;
drop trigger if exists athlth_competition_start_gate on public.athlth_tournaments;
create trigger athlth_competition_start_gate
before update on public.athlth_tournaments
for each row execute function private.athlth_competition_start_gate();
revoke all on function private.athlth_competition_start_gate()
from public,anon,authenticated;