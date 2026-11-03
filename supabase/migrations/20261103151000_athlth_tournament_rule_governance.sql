-- Tournament rule governance: owner-managed or group-selected before start.
-- Original data and workouts remain unchanged; all mutable actions use RPC.
create or replace function private.athlth_validate_activity_types(p_types text[])
returns boolean language sql immutable set search_path='' as $$
 select p_types is not null
    and cardinality(p_types) between 1 and 6
    and p_types <@ array['running','strength','cycling','walking','swimming','hiking']::text[]
    and (select count(distinct value)=cardinality(p_types) from unnest(p_types) value)
$$;

create or replace function public.athlth_tournament_create_with_rules(
 p_title text,p_format text,p_club uuid,p_season uuid,
 p_group_size integer,p_qualifiers integer,p_invitees uuid[],
 p_warmup_titles text[],p_exercise_mode text,p_exercise_count integer,
 p_proposals_close timestamptz,p_votes_close timestamptz,
 p_approve_player_changes boolean,p_allowed_activities text[],
 p_rules_authority text,p_cadence_days integer,p_completion_hours integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_tournament uuid;
 v_proposal uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if not private.athlth_validate_activity_types(p_allowed_activities) or
    p_rules_authority not in ('owner','group') or
    p_cadence_days not between 1 and 28 or
    p_completion_hours not between 1 and 672 then
    raise exception 'Invalid tournament activity or schedule rules';
 end if;
 v_tournament:=public.athlth_tournament_create_configured(
   p_title,p_format,p_club,p_season,p_group_size,p_qualifiers,
   p_invitees,p_warmup_titles,p_exercise_mode,p_exercise_count,
   p_proposals_close,p_votes_close,p_approve_player_changes
 );
 update public.athlth_tournaments
   set allowed_activities=p_allowed_activities,
       rules_authority=p_rules_authority,
       cadence_days=p_cadence_days,
       completion_hours=p_completion_hours,
       rules_confirmed_at=case when p_rules_authority='owner' then now()
                               else null end
 where id=v_tournament;
 if p_rules_authority='group' then
   insert into public.athlth_tournament_rule_proposals(
      tournament_id,proposer_id,allowed_activities,cadence_days,completion_hours
   ) values(v_tournament,auth.uid(),p_allowed_activities,
            p_cadence_days,p_completion_hours) returning id into v_proposal;
   insert into public.athlth_tournament_rule_votes(
      tournament_id,voter_id,proposal_id
   ) values(v_tournament,auth.uid(),v_proposal);
 end if;
 insert into public.athlth_tournament_audit(
      tournament_id,actor_id,event,info
 ) values(v_tournament,auth.uid(),'rules_created',
   jsonb_build_object('authority',p_rules_authority,'activities',p_allowed_activities,
                      'cadence_days',p_cadence_days,'completion_hours',p_completion_hours));
 return v_tournament;
end;
$$;

create or replace function public.athlth_tournament_propose_rules(
 p_tournament uuid,p_allowed_activities text[],
 p_cadence_days integer,p_completion_hours integer
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_t public.athlth_tournaments%rowtype;
 v_id uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into v_t from public.athlth_tournaments
   where id=p_tournament for update;
 if not found or v_t.status<>'inviting' or
    v_t.rules_authority<>'group' or
    v_t.rules_confirmed_at is not null or
    not private.athlth_tournament_is_accepted(p_tournament) or
    not private.athlth_validate_activity_types(p_allowed_activities) or
    p_cadence_days not between 1 and 28 or
    p_completion_hours not between 1 and 672 then
    raise exception 'Rules cannot be proposed now';
 end if;
 if (select count(*) from public.athlth_tournament_rule_proposals
     where tournament_id=p_tournament)>=16 then
    raise exception 'At most 16 rule proposals may be discussed';
 end if;
 insert into public.athlth_tournament_rule_proposals(
      tournament_id,proposer_id,allowed_activities,cadence_days,completion_hours
 ) values(p_tournament,auth.uid(),p_allowed_activities,
          p_cadence_days,p_completion_hours)
 returning id into v_id;
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

revoke all on function private.athlth_validate_activity_types(text[])
 from public,anon,authenticated;
revoke all on function public.athlth_tournament_create_with_rules(
 text,text,uuid,uuid,integer,integer,uuid[],text[],text,integer,
 timestamptz,timestamptz,boolean,text[],text,integer,integer)
 from public,anon;
revoke all on function public.athlth_tournament_propose_rules(
 uuid,text[],integer,integer) from public,anon;
revoke all on function public.athlth_tournament_vote_rules(uuid) from public,anon;
grant execute on function public.athlth_tournament_create_with_rules(
 text,text,uuid,uuid,integer,integer,uuid[],text[],text,integer,
 timestamptz,timestamptz,boolean,text[],text,integer,integer)
 to authenticated;
grant execute on function public.athlth_tournament_propose_rules(
 uuid,text[],integer,integer) to authenticated;
grant execute on function public.athlth_tournament_vote_rules(uuid) to authenticated;
