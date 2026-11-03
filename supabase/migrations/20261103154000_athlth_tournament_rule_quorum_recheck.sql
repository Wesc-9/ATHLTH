-- Re-evaluate rule majority after the final invitation response.
create or replace function private.athlth_tournament_confirm_rule_majority(
 p_tournament uuid
) returns boolean language plpgsql security definer set search_path='' as $$
declare
 v_t public.athlth_tournaments%rowtype;
 v_p public.athlth_tournament_rule_proposals%rowtype;
 v_best_id uuid;
 v_votes integer;
 v_accepted integer;
 v_pending integer;
begin
 select * into v_t from public.athlth_tournaments
 where id=p_tournament for update;
 if not found or v_t.status<>'inviting' or
    v_t.rules_authority<>'group' or v_t.rules_confirmed_at is not null then
   return false;
 end if;
 select count(*) into v_accepted from public.athlth_tournament_entries
 where tournament_id=p_tournament and response='accepted' and removed_at is null;
 select count(*) into v_pending from public.athlth_tournament_entries
 where tournament_id=p_tournament and response='invited' and removed_at is null;
 if v_pending>0 or v_accepted<2 then return false; end if;

 select votes.proposal_id,count(*) into v_best_id,v_votes
 from public.athlth_tournament_rule_votes votes
 join public.athlth_tournament_entries entrants
 on entrants.tournament_id=votes.tournament_id and
    entrants.user_id=votes.voter_id and entrants.response='accepted' and
    entrants.removed_at is null
 where votes.tournament_id=p_tournament
 group by votes.proposal_id
 order by count(*) desc,votes.proposal_id limit 1;

 if v_best_id is null or v_votes<=v_accepted/2 then return false; end if;
 select * into v_p from public.athlth_tournament_rule_proposals
 where id=v_best_id and tournament_id=p_tournament;
 if not found then return false; end if;

 update public.athlth_tournaments
 set allowed_activities=v_p.allowed_activities,
     cadence_days=v_p.cadence_days,
     completion_hours=v_p.completion_hours,
     rules_confirmed_at=now()
 where id=p_tournament;
 update public.athlth_tournament_entries
 set is_ready=false,ready_at=null where tournament_id=p_tournament;
 insert into public.athlth_tournament_audit(tournament_id,actor_id,event,info)
 values(p_tournament,v_p.proposer_id,'group_rules_confirmed',
   jsonb_build_object('proposal',v_best_id,'votes',v_votes,
      'accepted',v_accepted,'cadence_days',v_p.cadence_days,
      'completion_hours',v_p.completion_hours,
      'activities',v_p.allowed_activities));
 return true;
end;
$$;

create or replace function private.athlth_tournament_recheck_rule_votes()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.response is distinct from old.response or
    new.removed_at is distinct from old.removed_at then
   perform private.athlth_tournament_confirm_rule_majority(new.tournament_id);
 end if;
 return new;
end;
$$;

drop trigger if exists athlth_rule_recheck_on_invitation
 on public.athlth_tournament_entries;
create trigger athlth_rule_recheck_on_invitation
after update of response,removed_at on public.athlth_tournament_entries
for each row execute function private.athlth_tournament_recheck_rule_votes();

revoke all on function private.athlth_tournament_confirm_rule_majority(uuid),
 private.athlth_tournament_recheck_rule_votes() from public,anon,authenticated;
