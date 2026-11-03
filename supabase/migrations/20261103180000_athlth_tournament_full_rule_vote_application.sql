-- Full rule package can be proposed and voted on by the group.
-- Apply public visibility and authorized rescheduling policy as part of
-- the exact approved rules, not as quiet owner-selected defaults.
create or replace function public.athlth_tournament_create_full_rules(
 p_title text, p_format text, p_club uuid, p_season uuid,
 p_group_size integer, p_qualifiers integer, p_invitees uuid[],
 p_warmup_titles text[], p_exercise_mode text, p_exercise_count integer,
 p_proposals_close timestamptz, p_votes_close timestamptz,
 p_approve_player_changes boolean, p_allowed_activities text[],
 p_rules_authority text, p_cadence_days integer, p_completion_hours integer,
 p_rotation_mode text, p_rest_weekdays integer[],
 p_proof_mode text, p_public_results boolean,
 p_allow_extensions boolean, p_win_points integer, p_draw_points integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_id uuid;
 v_rest integer[];
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_rotation_mode not in ('all','sequence','shuffle')
    or p_proof_mode not in ('opponent','verified')
    or p_win_points not between 1 and 10
    or p_draw_points not between 0 and least(p_win_points-1,3)
    or p_rest_weekdays is null
    or not (p_rest_weekdays <@ array[1,2,3,4,5,6,7]::integer[])
    or cardinality(p_rest_weekdays)>=7
    or (select count(distinct x) from unnest(p_rest_weekdays) x)
          <> cardinality(p_rest_weekdays) then
   raise exception 'Invalid advanced tournament rules';
 end if;
 v_id:=public.athlth_tournament_create_with_rules(
   p_title,p_format,p_club,p_season,p_group_size,p_qualifiers,p_invitees,
   p_warmup_titles,p_exercise_mode,p_exercise_count,p_proposals_close,
   p_votes_close,p_approve_player_changes,p_allowed_activities,
   p_rules_authority,p_cadence_days,p_completion_hours
 );
 update public.athlth_tournaments
 set rotation_mode=p_rotation_mode,
     rest_weekdays=p_rest_weekdays,proof_mode=p_proof_mode,
     public_results=coalesce(p_public_results,false),
     allow_extensions=coalesce(p_allow_extensions,true),
     win_points=p_win_points,draw_points=p_draw_points
 where id=v_id;
 -- Replace default initial group proposal so the majority vote covers the
 -- whole rule package rather than quietly accepting owner's advanced rules.
 update public.athlth_tournament_rule_proposals
 set rotation_mode=p_rotation_mode,rest_weekdays=p_rest_weekdays,
     proof_mode=p_proof_mode,win_points=p_win_points,
     draw_points=p_draw_points,
     public_results=coalesce(p_public_results,false),
     allow_extensions=coalesce(p_allow_extensions,true)
 where tournament_id=v_id;
 insert into public.athlth_tournament_audit(
   tournament_id,actor_id,event,info
 ) values(v_id,auth.uid(),'advanced_rules_created',
   jsonb_build_object('rotation',p_rotation_mode,
      'rest_weekdays',p_rest_weekdays,'proof_mode',p_proof_mode,
      'public_results',p_public_results,'extensions',p_allow_extensions,
      'win_points',p_win_points,'draw_points',p_draw_points));
 return v_id;
end;
$$;

create or replace function public.athlth_tournament_vote_rules(
 p_proposal uuid
) returns boolean language plpgsql security definer set search_path='' as $$
declare
 v_p public.athlth_tournament_rule_proposals%rowtype;
 v_t public.athlth_tournaments%rowtype;
 v_accepted integer;
 v_pending integer;
 v_votes integer;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into v_p from public.athlth_tournament_rule_proposals
   where id=p_proposal;
 if not found then raise exception 'Rule proposal does not exist'; end if;
 select * into v_t from public.athlth_tournaments
   where id=v_p.tournament_id for update;
 if v_t.status<>'inviting' or v_t.rules_authority<>'group' or
    v_t.rules_confirmed_at is not null or
    not private.athlth_tournament_is_accepted(v_t.id) then
    raise exception 'Voting is closed';
 end if;
 insert into public.athlth_tournament_rule_votes(
      tournament_id,voter_id,proposal_id
 ) values(v_t.id,auth.uid(),p_proposal)
 on conflict(tournament_id,voter_id) do update
      set proposal_id=excluded.proposal_id,voted_at=now();
 select count(*) into v_accepted from public.athlth_tournament_entries
   where tournament_id=v_t.id and response='accepted' and removed_at is null;
 select count(*) into v_pending from public.athlth_tournament_entries
   where tournament_id=v_t.id and response='invited' and removed_at is null;
 select count(*) into v_votes from public.athlth_tournament_rule_votes votes
   join public.athlth_tournament_entries entries
     on entries.tournament_id=votes.tournament_id
    and entries.user_id=votes.voter_id
    and entries.response='accepted' and entries.removed_at is null
   where votes.tournament_id=v_t.id and votes.proposal_id=p_proposal;
 if v_pending=0 and v_accepted>=2 and v_votes>v_accepted/2 then
   update public.athlth_tournaments
      set allowed_activities=v_p.allowed_activities,
          cadence_days=v_p.cadence_days,
          completion_hours=v_p.completion_hours,
          rotation_mode=v_p.rotation_mode,
          rest_weekdays=v_p.rest_weekdays,
          proof_mode=v_p.proof_mode,
          win_points=v_p.win_points,draw_points=v_p.draw_points,
          public_results=v_p.public_results,
          allow_extensions=v_p.allow_extensions,
          rule_version=rule_version+1,
          rules_confirmed_at=now()
    where id=v_t.id;
   update public.athlth_tournament_entries
      set is_ready=false,ready_at=null where tournament_id=v_t.id;
   insert into public.athlth_tournament_audit(
      tournament_id,actor_id,event,info
   ) values(v_t.id,auth.uid(),'group_rules_confirmed',
     jsonb_build_object('proposal',p_proposal,'votes',v_votes,
       'accepted',v_accepted,'cadence_days',v_p.cadence_days,
       'completion_hours',v_p.completion_hours,
       'activities',v_p.allowed_activities));
   return true;
 end if;
 return false;
end;
$$;


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
     rotation_mode=v_p.rotation_mode,
     rest_weekdays=v_p.rest_weekdays,
     proof_mode=v_p.proof_mode,
     win_points=v_p.win_points,draw_points=v_p.draw_points,
     public_results=v_p.public_results,
     allow_extensions=v_p.allow_extensions,
     rule_version=rule_version+1,
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

