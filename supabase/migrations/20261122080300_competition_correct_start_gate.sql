CREATE OR REPLACE FUNCTION private.athlth_competition_start_gate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if old.status is distinct from new.status and new.status='active' and
    new.planned_starts_at is not null and
    clock_timestamp()<new.planned_starts_at then
    raise exception 'Competition cannot start before its planned date';
 end if;
 if old.status is distinct from new.status and new.status='active' and
    new.competition_settings_applied and
    (select count(*) from public.athlth_tournament_entries e
     where e.tournament_id=new.id and e.response='accepted'
       and e.removed_at is null)<(case when new.format='cup' then 4 else 2 end) then
    raise exception 'Liga requires two; cup requires four accepted athletes';
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
    old.loser_consequence is distinct from new.loser_consequence or
    old.start_mode is distinct from new.start_mode or
    old.required_environment is distinct from new.required_environment or
    old.meeting_place is distinct from new.meeting_place or
    old.meeting_lat is distinct from new.meeting_lat or
    old.meeting_lon is distinct from new.meeting_lon)
 then raise exception 'Competition rules are locked'; end if;
 return new;
end;
$function$
