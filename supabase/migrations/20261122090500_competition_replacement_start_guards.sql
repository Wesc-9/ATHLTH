CREATE OR REPLACE FUNCTION private.athlth_competition_auto_start()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; started integer:=0;
begin
 for r in select t.id from public.athlth_tournaments t
   where t.competition_settings_applied and t.status='inviting'
   and t.start_mode in ('when_ready','scheduled')
   and (t.unanswered_policy<>'replace' or t.replacement_until is null)
   and (t.start_mode='when_ready' or (t.planned_starts_at is not null
      and t.planned_starts_at<=clock_timestamp()))
   and t.rules_confirmed_at is not null
   and t.exercise_selection_finalized_at is not null
   and not exists (select 1 from public.athlth_tournament_entries e
       where e.tournament_id=t.id and e.response='invited')
   and not exists (select 1 from public.athlth_tournament_entries e
       where e.tournament_id=t.id and e.response='accepted'
         and (e.is_ready is not true or e.removed_at is not null
              or e.agreed_rule_version is distinct from t.rule_version))
   and (select count(*) from public.athlth_tournament_entries e
       where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null)
       >=case when t.format='cup' then 4 else 2 end
   order by t.created_at limit 100
 loop
   begin
     perform private.athlth_competition_start_internal(r.id);
     started:=started+1;
   exception when others then
     -- Do not fail the batch; keep the competition waiting for a valid setup.
     raise warning 'Competition automatic start %: %',r.id,sqlerrm;
   end;
 end loop;
 return started;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.athlth_competition_start_internal(p_tournament uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    select * into v_t from public.athlth_tournaments
    where id=p_tournament for update;
    if not found or not v_t.competition_settings_applied then
        raise exception 'Not a configured competition';
    end if;
    if v_actor is not null then
       if v_actor<>v_t.owner_id or v_t.start_mode<>'manual' then
          raise exception 'Only the organizer can start manual competitions';
       end if;
    elsif v_t.start_mode='manual' then
       raise exception 'Manual competitions need an organizer';
    end if;
    if v_t.start_mode='scheduled' and
       (v_t.planned_starts_at is null or clock_timestamp()<v_t.planned_starts_at) then
       raise exception 'Scheduled start time is not reached';
    end if;
    if v_t.unanswered_policy='replace' and v_t.replacement_until is not null
    then raise exception 'Finish replacement before starting'; end if;
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
    if (v_t.format='cup' and v_count<4)
       or (v_t.format in ('league','groups') and v_count<2)
    then raise exception 'League requires two; cup requires four accepted athletes'; end if;
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
    ) values(p_tournament,coalesce(v_actor,v_t.owner_id),'started',
        jsonb_build_object('accepted',v_count,'warmups',v_warmups));
end;
$function$
;
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
    old.meeting_lon is distinct from new.meeting_lon or
    old.invitation_days is distinct from new.invitation_days or
    old.unanswered_policy is distinct from new.unanswered_policy or
    old.allow_feed_post is distinct from new.allow_feed_post)
 then raise exception 'Competition rules are locked'; end if;
 return new;
end;
$function$
;
create or replace function public.athlth_tournament_finish_replacement(
 p_tournament uuid
) returns void language plpgsql security definer set search_path='' as $f$
declare t public.athlth_tournaments%rowtype; n integer;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament for update;
 if not found or t.owner_id<>auth.uid() or t.status<>'inviting'
   or t.unanswered_policy<>'replace' or t.replacement_until is null then
   raise exception 'Only the organizer can close an active replacement window';
 end if;
 if exists(select 1 from public.athlth_tournament_entries e
    where e.tournament_id=t.id and e.response='invited') then
   raise exception 'There are still pending invitations'; end if;
 select count(*) into n from public.athlth_tournament_entries e
  where e.tournament_id=t.id and e.response='accepted'
    and e.removed_at is null;
 if n<(case when t.format='cup' then 4 else 2 end) then
  raise exception 'Not enough athletes accepted'; end if;
 update public.athlth_tournaments set replacement_until=null where id=t.id;
 insert into public.athlth_tournament_audit(tournament_id,actor_id,event)
 values(t.id,auth.uid(),'replacement_window_closed');
end;$f$;
revoke all on function public.athlth_tournament_finish_replacement(uuid) from public,anon;
grant execute on function public.athlth_tournament_finish_replacement(uuid) to authenticated;