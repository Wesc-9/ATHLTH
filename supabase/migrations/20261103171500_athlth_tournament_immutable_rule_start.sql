-- Every athlete must acknowledge one immutable final rule version.
-- Group majority approves all advanced options, not just the cadence.
create or replace function public.athlth_tournament_set_ready(
 p_tournament uuid,p_ready boolean
) returns void language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();
 v_t public.athlth_tournaments%rowtype;
begin
 if v_user is null then raise exception 'Sign in required'; end if;
 select * into v_t from public.athlth_tournaments
   where id=p_tournament for update;
 if v_t.status<>'inviting' then raise exception 'Lobby is closed'; end if;
 if p_ready and v_t.exercise_selection_finalized_at is null then
   raise exception 'The exercises must be finalized before marking ready';
 end if;
 if p_ready and v_t.rules_confirmed_at is null then
    raise exception 'All tournament rules must be approved first';
 end if;
 if p_ready and not exists(
     select 1 from public.athlth_tournament_entries
     where tournament_id=p_tournament and user_id=v_user
       and response='accepted' and removed_at is null
       and agreed_rule_version=v_t.rule_version
   ) then
    raise exception 'Read and accept the final rules before pressing Ready';
 end if;
 update public.athlth_tournament_entries
   set is_ready=coalesce(p_ready,false),
       ready_at=case when p_ready then now() else null end
 where tournament_id=p_tournament and user_id=v_user
   and response='accepted' and removed_at is null;
 if not found then raise exception 'Only accepted athletes can mark ready'; end if;
end;
$$;

create or replace function public.athlth_tournament_start(
    p_tournament uuid
) returns void language plpgsql security definer
set search_path='' as $$
declare
    v_actor uuid := auth.uid();
    v_t public.athlth_tournaments%rowtype;
    v_members uuid[];
    v_count integer;
    v_pending integer;
    v_groups integer;
    v_group integer;
    v_group_members uuid[];
    v_warmups integer;
    v_index integer;
begin
    if v_actor is null then raise exception 'Sign in required'; end if;
    select * into v_t from public.athlth_tournaments
    where id=p_tournament for update;
    if not found or v_t.owner_id<>v_actor then
        raise exception 'Only the organizer can start the competition';
    end if;
    if v_t.status<>'inviting' then
        raise exception 'Tournament is not awaiting invitations';
    end if;
    if v_t.rules_confirmed_at is null then
       raise exception 'Group rules must be approved before starting';
    end if;
    if v_t.exercise_selection_finalized_at is null or
       (select count(*) from public.athlth_tournament_exercise_candidates
        where tournament_id=p_tournament and selected_position is not null)
         <> v_t.exercise_count then
        raise exception 'Finalize the exercise list before starting';
    end if;
    if exists(
        select 1 from public.athlth_tournament_entries e
        where e.tournament_id=p_tournament and e.response='accepted'
          and (e.is_ready is not true or e.removed_at is not null
              or e.agreed_rule_version is distinct from v_t.rule_version)
    ) then
        raise exception 'All accepted participants must press Ready';
    end if;
    select count(*) into v_pending from public.athlth_tournament_entries
    where tournament_id=p_tournament and response='invited';
    if v_pending<>0 then
        raise exception 'Wait for every invited athlete to respond';
    end if;
    -- Fair, tamper-resistant draw. The organizer is NOT automatically
    -- assigned the first seed or any potential bye.
    select array_agg(user_id order by draw_key,user_id) into v_members
    from (
        select user_id, random() as draw_key
        from public.athlth_tournament_entries
        where tournament_id=p_tournament and response='accepted'
    ) shuffled;
    v_count := coalesce(array_length(v_members,1),0);
    if v_count<2 then raise exception 'At least two athletes must accept'; end if;
    for v_index in 1..v_count loop
        update public.athlth_tournament_entries
           set draw_position=v_index
         where tournament_id=p_tournament
           and user_id=v_members[v_index];
    end loop;

    if v_t.format='groups' and v_count<=v_t.group_size then
        raise exception 'Choose more athletes than one group, or use league';
    end if;
    select count(*) into v_warmups from public.athlth_tournament_practice
    where tournament_id=p_tournament;
    if v_warmups>0 then
        perform private.athlth_schedule_round_robin(
            p_tournament,v_members,'warmup',null,v_warmups
        );
    end if;
    if v_t.format='league' then
        perform private.athlth_schedule_round_robin(
            p_tournament,v_members,'league',null,null
        );
    elsif v_t.format='groups' then
        v_groups := ceil(v_count::numeric / v_t.group_size)::integer;
        if v_count<2*v_groups or
           v_t.qualifiers_per_group>floor(v_count::numeric/v_groups) then
            raise exception 'Group size or qualifiers would create an unfair one-person group';
        end if;
        for v_index in 1..v_count loop
            update public.athlth_tournament_entries
               set group_index=(v_index-1) % v_groups
             where tournament_id=p_tournament
               and user_id=v_members[v_index];
        end loop;
        for v_group in 0..(v_groups-1) loop
            select array_agg(user_id order by draw_position) into v_group_members
            from public.athlth_tournament_entries
            where tournament_id=p_tournament and response='accepted'
              and group_index=v_group;
            perform private.athlth_schedule_round_robin(
                p_tournament,v_group_members,'group',v_group,null
            );
        end loop;
    else
        perform private.athlth_schedule_knockout(
            p_tournament,v_members,'cup',1
        );
    end if;
    update public.athlth_tournaments
    set status='active',started_at=now(),rules_frozen_at=now() where id=p_tournament;
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event,info
    ) values(p_tournament,v_actor,'started',
        jsonb_build_object('accepted',v_count,'warmups',v_warmups));
end;
$$;create or replace function public.athlth_tournament_suggest_activity_template(
 p_tournament uuid,p_template uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();
 v_t public.athlth_tournaments%rowtype;
 v_type text;
 v_id uuid;
begin
 if v_user is null then raise exception 'Sign in required'; end if;
 select * into v_t from public.athlth_tournaments
   where id=p_tournament for update;
 if not found or v_t.status<>'inviting' or
    v_t.exercise_selection_finalized_at is not null or
    v_t.rules_confirmed_at is null then
    raise exception 'Activity nominations are not open';
 end if;
 if (v_t.exercise_mode='owner' and v_t.owner_id<>v_user) or
    (v_t.exercise_mode<>'owner' and not private.athlth_tournament_is_accepted(p_tournament)) then
    raise exception 'Not allowed to nominate this activity';
 end if;
 if v_t.exercise_mode='vote' and now()>=v_t.proposals_close_at then
   raise exception 'Activity nominations have closed';
 end if;
 select activity_type into v_type
 from public.athlth_tournament_activity_templates
 where id=p_template and is_active;
 if v_type is null or not (v_type=any(v_t.allowed_activities)) then
   raise exception 'Selected activity type is not permitted';
 end if;
 if (select count(*) from public.athlth_tournament_exercise_candidates
     where tournament_id=p_tournament)>=500 then
   raise exception 'Maximum number of suggestions reached';
 end if;
 insert into public.athlth_tournament_exercise_candidates(
    tournament_id,activity_template_id,suggested_by
 ) values(p_tournament,p_template,v_user)
 on conflict (tournament_id,activity_template_id) do nothing returning id into v_id;
 if v_id is null then
   select id into v_id from public.athlth_tournament_exercise_candidates
   where tournament_id=p_tournament and activity_template_id=p_template;
 end if;
 return v_id;
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


revoke all on function public.athlth_tournament_set_ready(uuid,boolean),
 public.athlth_tournament_start(uuid),public.athlth_tournament_vote_rules(uuid)
 from public,anon;
grant execute on function public.athlth_tournament_set_ready(uuid,boolean),
 public.athlth_tournament_start(uuid),public.athlth_tournament_vote_rules(uuid)
 to authenticated;
revoke all on function private.athlth_tournament_confirm_rule_majority(uuid)
 from public,anon,authenticated;
