-- Compatibility patch: tournament start uses the same confirmed-bye
-- semantics as the opponent-approval and advancement RPCs. Reject single-
-- athlete groups and impossible qualification counts before allocating games.
create or replace function private.athlth_schedule_knockout(
    p_tournament uuid, p_members uuid[], p_phase text,
    p_round integer
) returns void language plpgsql security definer
set search_path='' as $$
declare
    v_count integer := coalesce(array_length(p_members,1),0);
    v_capacity integer := 2;
    v_byes integer;
    v_position integer := 1;
    v_match integer;
    v_away uuid;
begin
    if p_phase not in ('cup','playoff') or v_count < 2 or v_count > 128 then
        raise exception 'Invalid knockout roster';
    end if;
    while v_capacity < v_count loop
        v_capacity := v_capacity * 2;
    end loop;
    v_byes := v_capacity - v_count;
    for v_match in 1..(v_capacity/2) loop
        if v_match <= v_byes then
            v_away := null;
        else
            v_away := p_members[v_position + 1];
        end if;
        insert into public.athlth_tournament_matches(
            tournament_id, phase, round_number, group_index, slot_index,
            home_id, away_id, status
        ) values(
            p_tournament, p_phase, p_round, null, v_match,
            p_members[v_position], v_away,
            case when v_away is null then 'confirmed' else 'scheduled' end
        );
        if v_away is null then v_position:=v_position+1;
        else v_position:=v_position+2; end if;
    end loop;
end;
$$;

-- With no shared session started, invitations may still be declined. The
-- organizer can start only once everyone has answered, and at least two
-- competitors have accepted. All scheduling is serialized on this row.
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
    select count(*) into v_pending from public.athlth_tournament_entries
    where tournament_id=p_tournament and response='invited';
    if v_pending<>0 then
        raise exception 'Wait for every invited athlete to respond';
    end if;
    select array_agg(user_id order by seed) into v_members
    from public.athlth_tournament_entries
    where tournament_id=p_tournament and response='accepted';
    v_count := coalesce(array_length(v_members,1),0);
    if v_count<2 then raise exception 'At least two athletes must accept'; end if;
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
            select array_agg(user_id order by seed) into v_group_members
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
    set status='active',started_at=now() where id=p_tournament;
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event,info
    ) values(p_tournament,v_actor,'started',
        jsonb_build_object('accepted',v_count,'warmups',v_warmups));
end;
$$;

revoke all on function private.athlth_schedule_knockout(
 uuid,uuid[],text,integer) from public,anon,authenticated;
revoke all on function public.athlth_tournament_start(uuid)
 from public,anon;
grant execute on function public.athlth_tournament_start(uuid)
 to authenticated;
