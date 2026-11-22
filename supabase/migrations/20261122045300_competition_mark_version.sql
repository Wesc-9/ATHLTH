create or replace function private.athlth_competition_mark_settings()
returns trigger language plpgsql set search_path='' as $fn$
begin
 if old.status='inviting' and old.rules_frozen_at is null
 then new.competition_settings_applied:=true; end if;
 return new;
end;
$fn$;
drop trigger if exists athlth_competition_mark_settings on public.athlth_tournaments;
create trigger athlth_competition_mark_settings
before update of planned_starts_at,release_mode,release_every,release_unit,
 invitation_permission,join_approval,allowed_actions,prohibited_actions,
 prize_first,prize_second,prize_third,loser_consequence
on public.athlth_tournaments
for each row execute function private.athlth_competition_mark_settings();
revoke all on function private.athlth_competition_mark_settings()
from public,anon,authenticated;