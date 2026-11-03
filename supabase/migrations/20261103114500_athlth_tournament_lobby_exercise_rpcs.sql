-- Exercise selection workflow. Winner selection happens once on the server;
-- equal vote counts are resolved by an immutable, randomly generated UUID.
create or replace function public.athlth_tournament_create_configured(
 p_title text,p_format text,p_club uuid,p_season uuid,
 p_group_size integer,p_qualifiers integer,p_invitees uuid[],
 p_warmup_titles text[],p_exercise_mode text,p_exercise_count integer,
 p_proposals_close timestamptz,p_votes_close timestamptz,
 p_approve_player_changes boolean
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_id uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_exercise_mode not in ('owner','open','vote') or
    p_exercise_count not between 1 and 12 then
    raise exception 'Invalid exercise selection';
 end if;
 if p_exercise_mode='vote' and
    (p_proposals_close is null or p_votes_close is null or
     p_proposals_close<=clock_timestamp()+interval '2 minutes' or
     p_votes_close<=p_proposals_close or
     p_votes_close>clock_timestamp()+interval '30 days') then
     raise exception 'Voting requires future proposal and ballot deadlines';
 end if;
 v_id := public.athlth_tournament_create(
     p_title,p_format,p_club,p_season,
     p_group_size,p_qualifiers,p_invitees,p_warmup_titles
 );
 update public.athlth_tournaments
    set exercise_mode=p_exercise_mode,
        exercise_count=p_exercise_count,
        proposals_close_at=case when p_exercise_mode='vote'
             then p_proposals_close else null end,
        votes_close_at=case when p_exercise_mode='vote'
             then p_votes_close else null end,
        approve_player_changes=coalesce(p_approve_player_changes,false)
  where id=v_id;
 return v_id;
end;
$$;

create or replace function public.athlth_tournament_suggest_exercise(
 p_tournament uuid,p_exercise uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_t public.athlth_tournaments%rowtype;
 v_candidate uuid;
 v_user uuid:=auth.uid();
begin
 if v_user is null then raise exception 'Sign in required'; end if;
 select * into v_t from public.athlth_tournaments where id=p_tournament for update;
 if not found or v_t.status<>'inviting' or
   v_t.exercise_selection_finalized_at is not null then
   raise exception 'Exercise suggestions are closed';
 end if;
 if (v_t.exercise_mode='owner' and v_user<>v_t.owner_id) or
    (v_t.exercise_mode<>'owner' and not private.athlth_tournament_is_accepted(p_tournament)) then
   raise exception 'Cannot suggest exercises in this tournament';
 end if;
 if v_t.exercise_mode='vote' and clock_timestamp()>=v_t.proposals_close_at then
   raise exception 'Exercise nomination period has ended';
 end if;
 if not exists(select 1 from public.exercise_catalog
               where id=p_exercise and is_published) then
   raise exception 'Choose an available exercise from the library';
 end if;
 if (select count(*) from public.athlth_tournament_exercise_candidates
      where tournament_id=p_tournament)>=500 then
   raise exception 'Tournament suggestion limit reached';
 end if;
 insert into public.athlth_tournament_exercise_candidates(
      tournament_id,exercise_id,suggested_by
 ) values(p_tournament,p_exercise,v_user)
 on conflict (tournament_id,exercise_id) do nothing returning id into v_candidate;
 if v_candidate is null then
    select id into v_candidate from public.athlth_tournament_exercise_candidates
     where tournament_id=p_tournament and exercise_id=p_exercise;
 end if;
 return v_candidate;
end;
$$;

create or replace function public.athlth_tournament_vote_exercise(
 p_candidate uuid,p_voted boolean
) returns integer language plpgsql security definer set search_path='' as $$
declare
 v_t public.athlth_tournaments%rowtype;
 v_user uuid:=auth.uid();
 v_id uuid;
 v_count integer;
begin
 if v_user is null then raise exception 'Sign in required'; end if;
 select tournament_id into v_id
 from public.athlth_tournament_exercise_candidates where id=p_candidate;
 if v_id is null then raise exception 'Exercise candidate not found'; end if;
 select * into v_t from public.athlth_tournaments where id=v_id for update;
 if v_t.status<>'inviting' or v_t.exercise_mode<>'vote' or
    v_t.exercise_selection_finalized_at is not null or
    clock_timestamp()<v_t.proposals_close_at or
    clock_timestamp()>=v_t.votes_close_at or
    not private.athlth_tournament_is_accepted(v_t.id) then
    raise exception 'Exercise ballot is not open for this athlete';
 end if;
 if coalesce(p_voted,false) then
     insert into public.athlth_tournament_exercise_votes(
        tournament_id,candidate_id,voter_id
     ) values(v_id,p_candidate,v_user)
     on conflict do nothing;
 else
     delete from public.athlth_tournament_exercise_votes
     where candidate_id=p_candidate and voter_id=v_user;
 end if;
 select count(*) into v_count from public.athlth_tournament_exercise_votes
 where tournament_id=v_id and voter_id=v_user;
 if v_count>v_t.exercise_count then
     raise exception 'You may vote for at most % exercises',v_t.exercise_count;
 end if;
 return v_count;
end;
$$;

create or replace function public.athlth_tournament_finalize_exercises(
 p_tournament uuid
) returns uuid[] language plpgsql security definer set search_path='' as $$
declare
 v_t public.athlth_tournaments%rowtype;
 v_ids uuid[];
 v_user uuid:=auth.uid();
 v_index integer:=0;
 v_id uuid;
begin
 if v_user is null then raise exception 'Sign in required'; end if;
 select * into v_t from public.athlth_tournaments
    where id=p_tournament for update;
 if not found or v_t.owner_id<>v_user or v_t.status<>'inviting' then
    raise exception 'Only the organizer can finalize the invitation lobby';
 end if;
 if v_t.exercise_selection_finalized_at is not null then
    select array_agg(id order by selected_position) into v_ids
    from public.athlth_tournament_exercise_candidates
    where tournament_id=p_tournament and selected_position is not null;
    return coalesce(v_ids,array[]::uuid[]);
 end if;
 if v_t.exercise_mode='vote' and
    clock_timestamp()<v_t.votes_close_at then
    raise exception 'Wait until the ballot closes; abstentions are permitted';
 end if;
 if (select count(*) from public.athlth_tournament_exercise_candidates
       where tournament_id=p_tournament)<v_t.exercise_count then
    raise exception 'Not enough exercise candidates for this tournament';
 end if;
 for v_id in
   select c.id from public.athlth_tournament_exercise_candidates c
   left join (
     select candidate_id,count(*) as votes
     from public.athlth_tournament_exercise_votes
     where tournament_id=p_tournament group by candidate_id
   ) ballot on ballot.candidate_id=c.id
   where c.tournament_id=p_tournament
   order by case when v_t.exercise_mode='vote' then coalesce(ballot.votes,0)
                 else 0 end desc,
            case when v_t.exercise_mode='vote' then c.tie_break_key
                 else null end asc,
            c.created_at,c.id
   limit v_t.exercise_count
 loop
    v_index:=v_index+1;
    update public.athlth_tournament_exercise_candidates
      set selected_position=v_index where id=v_id;
 end loop;
 update public.athlth_tournaments set exercise_selection_finalized_at=now()
 where id=p_tournament;
 insert into public.athlth_tournament_audit(
     tournament_id,actor_id,event,info
 ) values(p_tournament,v_user,'exercises_finalized',
   jsonb_build_object('mode',v_t.exercise_mode,'selected',v_index,
                      'tie_break','stored_random_uuid'));
 select array_agg(id order by selected_position) into v_ids
 from public.athlth_tournament_exercise_candidates
 where tournament_id=p_tournament and selected_position is not null;
 return coalesce(v_ids,array[]::uuid[]);
end;
$$;

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
 update public.athlth_tournament_entries
   set is_ready=coalesce(p_ready,false),
       ready_at=case when p_ready then now() else null end
 where tournament_id=p_tournament and user_id=v_user
   and response='accepted' and removed_at is null;
 if not found then raise exception 'Only accepted athletes can mark ready'; end if;
end;
$$;

create or replace function public.athlth_tournament_send_lobby_message(
 p_tournament uuid,p_content text,p_announcement boolean default false
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_actor uuid:=auth.uid();
 v_t public.athlth_tournaments%rowtype;
 v_id uuid;
begin
 if v_actor is null then raise exception 'Sign in required'; end if;
 select * into v_t from public.athlth_tournaments
   where id=p_tournament;
 if not found or v_t.status not in ('inviting','active') or
    not private.athlth_tournament_is_accepted(p_tournament) then
    raise exception 'Only accepted athletes may use the lobby chat';
 end if;
 if p_announcement and v_actor<>v_t.owner_id then
    raise exception 'Only the organizer can send announcements';
 end if;
 if p_content is null or length(btrim(p_content)) not between 1 and 1000 then
    raise exception 'Message must contain between 1 and 1000 characters';
 end if;
 if (select count(*) from public.athlth_tournament_lobby_messages
   where tournament_id=p_tournament and author_id=v_actor
     and created_at>clock_timestamp()-interval '10 seconds') >=5 then
    raise exception 'Too many messages; try again shortly';
 end if;
 insert into public.athlth_tournament_lobby_messages(
     tournament_id,author_id,content,kind
 ) values(p_tournament,v_actor,btrim(p_content),
          case when p_announcement then 'announcement' else 'chat' end)
 returning id into v_id;
 return v_id;
end;
$$;
-- These RPCs perform explicit authorization; do not grant client writes.
revoke all on function public.athlth_tournament_create_configured(
 text,text,uuid,uuid,integer,integer,uuid[],text[],text,integer,
 timestamptz,timestamptz,boolean) from public,anon;
revoke all on function public.athlth_tournament_suggest_exercise(uuid,uuid),
 public.athlth_tournament_vote_exercise(uuid,boolean),
 public.athlth_tournament_finalize_exercises(uuid),
 public.athlth_tournament_set_ready(uuid,boolean),
 public.athlth_tournament_send_lobby_message(uuid,text,boolean) from public,anon;
grant execute on function public.athlth_tournament_create_configured(
 text,text,uuid,uuid,integer,integer,uuid[],text[],text,integer,
 timestamptz,timestamptz,boolean) to authenticated;
grant execute on function public.athlth_tournament_suggest_exercise(uuid,uuid),
 public.athlth_tournament_vote_exercise(uuid,boolean),
 public.athlth_tournament_finalize_exercises(uuid),
 public.athlth_tournament_set_ready(uuid,boolean),
 public.athlth_tournament_send_lobby_message(uuid,text,boolean) to authenticated;
