-- Competition stays active for the full published duration. After that,
-- 48 hours are reserved for evidence and consensus; unresolved rounds expire.
-- Never award points on timeout and never call an unresolved series a win.
alter table public.arena_series
 add column if not exists completion_reason text;
alter table public.arena_series
 add constraint arena_completion_reason_valid check (
   completion_reason is null or completion_reason in ('all_approved','deadline_unresolved')
 );

alter table public.arena_round_results
 drop constraint if exists arena_round_results_status_check;
alter table public.arena_round_results
 add constraint arena_round_results_status_check check(
    status in ('pending','approved','rejected','expired')
 );

create or replace function private.arena_propose_result_impl(
 p_round uuid, p_slots uuid[],p_evidence text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private as $$
declare v_s public.arena_series%rowtype;
v_result uuid;
v_slot uuid;
v_expected integer;
v_actor uuid:=(select auth.uid());
begin
  select s.* into v_s from public.arena_round_proposals r
  join public.arena_series s on s.id=r.series_id
  where r.id=p_round for update of s;
  if not found or v_s.status<>'active' then
    raise exception 'Round is not in an active series';
  end if;
  if not private.arena_is_organizer(v_s.id) then
    raise exception 'Organizer must propose the round outcome';
  end if;
  if now()>v_s.ends_at+interval '48 hours' then
    raise exception 'Result review window has closed';
  end if;
  if p_evidence is null or char_length(btrim(p_evidence)) not between 1 and 600 then
    raise exception 'Add an evidence note before submitting a result';
  end if;
  if p_slots is null or array_position(p_slots,null) is not null
    or (select count(distinct x) from unnest(p_slots) x)<>cardinality(p_slots) then
    raise exception 'Ranking must contain distinct, non-null slots';
  end if;
  select count(*) into v_expected from public.arena_series_members m
    where m.series_id=v_s.id and m.response in ('accepted','deleted');
  if v_s.scoring='winner' and cardinality(p_slots)<>1 then
    raise exception 'Winner scoring requires one winning slot';
  end if;
  if v_s.scoring='podium' and cardinality(p_slots)<>least(3,v_expected) then
    raise exception 'Podium scoring requires ranked first, second and third slots';
  end if;
  foreach v_slot in array p_slots loop
    if not exists(select 1 from public.arena_series_members m
         where m.slot_id=v_slot and m.series_id=v_s.id
         and m.response in ('accepted','deleted')) then
       raise exception 'Winner is not a competition slot';
    end if;
  end loop;
  insert into public.arena_round_results(series_id,round_id,proposed_by,ranked_slots,evidence_note)
  values(v_s.id,p_round,v_actor,p_slots,btrim(p_evidence)) returning id into v_result;
  -- Submission counts as the organizer's approval.
  insert into public.arena_round_result_votes(result_id,user_id,accepted)
  values(v_result,v_actor,true);
  insert into public.social_inbox_events(
    recipient_id,kind,title,message,entity_type,entity_id,actor_id
  )
  select m.user_id,'arena_round','Arena – rundens resultat',
    'Godkjenn eller avvis det foreslåtte resultatet.',
    'arena_series',v_s.id,v_actor
  from public.arena_series_members m
  where m.series_id=v_s.id and m.response='accepted' and m.user_id is not null
    and m.user_id<>v_actor;
  return v_result;
end; $$;


create or replace function private.arena_vote_result_impl(
 p_result uuid,p_accept boolean
) returns text language plpgsql security definer
set search_path=pg_catalog,public,private as $$
declare v_r public.arena_round_results%rowtype;
v_s public.arena_series%rowtype;
v_actor uuid:=(select auth.uid());
v_required int;
v_approved int;
v_points numeric(10,2);
v_slot uuid;
v_i integer;
v_round_count integer;
v_approved_count integer;
begin
  select * into v_r from public.arena_round_results where id=p_result for update;
  if not found or v_r.status<>'pending' then
    raise exception 'Result is not pending approval';
  end if;
  select * into v_s from public.arena_series where id=v_r.series_id for update;
  if v_s.status<>'active' then raise exception 'Series is not active'; end if;
  if now()>v_s.ends_at+interval '48 hours' then
    raise exception 'The result review window has closed';
  end if;
  if not exists(select 1 from public.arena_series_members m
   where m.series_id=v_s.id and m.user_id=v_actor and m.response='accepted') then
    raise exception 'Only accepted participants can approve results';
  end if;
  if exists(select 1 from public.arena_round_result_votes v
   where v.result_id=p_result and v.user_id=v_actor) then
    raise exception 'You already voted on this result';
  end if;
  insert into public.arena_round_result_votes(result_id,user_id,accepted)
  values(p_result,v_actor,p_accept);
  if not p_accept then
    update public.arena_round_results set status='rejected',decided_at=now()
    where id=p_result;
    return 'rejected';
  end if;
  select count(*) into v_required from public.arena_series_members m
   where m.series_id=v_s.id and m.response='accepted' and m.user_id is not null;
  select count(*) into v_approved from public.arena_round_result_votes v
    join public.arena_series_members m on m.user_id=v.user_id
      and m.series_id=v_s.id and m.response='accepted'
    where v.result_id=p_result and v.accepted;
  if v_required<>v_approved then return 'pending'; end if;

  for v_i in 1..cardinality(v_r.ranked_slots) loop
    v_slot := v_r.ranked_slots[v_i];
    if v_s.scoring='winner' then v_points:=1;
    else v_points:=greatest(4-v_i,1); end if;
    insert into public.arena_round_points(round_id,slot_id,points)
    values(v_r.round_id,v_slot,v_points);
    update public.arena_series_members
      set points=points+v_points where slot_id=v_slot and series_id=v_s.id;
    if not found then raise exception 'Competition score slot disappeared'; end if;
  end loop;
  update public.arena_round_results set status='approved',decided_at=now()
    where id=p_result;

  select count(*) into v_round_count from public.arena_round_proposals
    where series_id=v_s.id;
  select count(*) into v_approved_count from public.arena_round_results
    where series_id=v_s.id and status='approved';
  -- Award the approved round points now, but never finish the whole
  -- competition before its advertised duration ends.
  if v_round_count=v_approved_count and now()>=v_s.ends_at then
     update public.arena_series set status='completed',
       completed_at=now(),completion_reason='all_approved'
     where id=v_s.id;
  end if;
  insert into public.social_inbox_events(
    recipient_id,kind,title,message,entity_type,entity_id,actor_id
  )
  select m.user_id,'arena_round',
    case when v_round_count=v_approved_count and now()>=v_s.ends_at then 'Arena – mester kåret'
     else 'Arena – poeng oppdatert' end,
    case when v_round_count=v_approved_count and now()>=v_s.ends_at then 'Konkurransen er ferdig. Se sluttstillingen.'
     else 'Et runderesultat er godkjent. Se oppdatert poengstilling.' end,
    'arena_series',v_s.id,v_actor
  from public.arena_series_members m
  where m.series_id=v_s.id and m.response='accepted' and m.user_id is not null;
  return case when v_round_count=v_approved_count and now()>=v_s.ends_at
    then 'completed' else 'approved' end;
end; $$;


create or replace function private.arena_finalize_due_series(p_series uuid)
returns text language plpgsql security definer
set search_path=pg_catalog,public,private as $$
declare
 v_s public.arena_series%rowtype;
 v_total int;
 v_approved int;
 v_reason text;
begin
 select * into v_s from public.arena_series where id=p_series for update;
 if not found then return 'missing'; end if;
 if v_s.status <> 'active' or v_s.ends_at is null then
   return v_s.status;
 end if;
 if now()<v_s.ends_at then return 'active'; end if;
 select count(*) into v_total
 from public.arena_round_proposals where series_id=p_series;
 select count(*) into v_approved
 from public.arena_round_results
 where series_id=p_series and status='approved';
 if v_total<>v_approved and now()<v_s.ends_at+interval '48 hours' then
   return 'review';
 end if;

 v_reason := case when v_total=v_approved
   then 'all_approved' else 'deadline_unresolved' end;
 update public.arena_round_results
 set status='expired',decided_at=now()
 where series_id=p_series and status='pending';
 update public.arena_series
 set status='completed',completed_at=now(),completion_reason=v_reason
 where id=p_series and status='active';
 insert into public.social_inbox_events(
   recipient_id,kind,title,message,entity_type,entity_id,actor_id
 )
 select m.user_id,'arena_round',
   case when v_reason='all_approved'
     then 'Arena – konkurransen er ferdig'
     else 'Arena – konkurransen er avsluttet' end,
   case when v_reason='all_approved'
     then 'Alle runder er godkjent. Se sluttresultatet.'
     else 'Tidsfristen er ute. Uavklarte runder har ikke fått poeng.' end,
   'arena_series',p_series,v_s.owner_id
 from public.arena_series_members m
 where m.series_id=p_series and m.response='accepted' and m.user_id is not null;
 return 'completed';
end;
$$;

create or replace function private.arena_finalize_due_all()
returns integer language plpgsql security definer
set search_path=pg_catalog,public,private as $$
declare v_id uuid; v_count int := 0; v_status text;
begin
 for v_id in select id from public.arena_series
  where status='active' and ends_at<=now()
    and (ends_at+interval '48 hours'<=now() or
      not exists (
        select 1 from public.arena_round_proposals rp
        where rp.series_id=arena_series.id and
        not exists (
          select 1 from public.arena_round_results rr
          where rr.round_id=rp.id and rr.status='approved'
        )
      )
    ) loop
   v_status := private.arena_finalize_due_series(v_id);
   if v_status='completed' then v_count:=v_count+1; end if;
 end loop;
 return v_count;
end;
$$;

-- The API can safely run the same reconciliation upon opening Arena,
-- even if a scheduled cron check has not run yet.
create or replace function private.arena_refresh_my_deadlines()
returns integer language plpgsql security definer
set search_path=pg_catalog,public,private as $$
declare v_id uuid; v_count int := 0; v_status text;
begin
 if auth.uid() is null then return 0; end if;
 for v_id in select distinct s.id from public.arena_series s
  where s.status='active' and s.ends_at<=now() and (
    s.owner_id=auth.uid() or
    exists (select 1 from public.arena_series_members m
      where m.series_id=s.id and m.user_id=auth.uid()
        and m.response='accepted')
  ) loop
  v_status := private.arena_finalize_due_series(v_id);
  if v_status='completed' then v_count:=v_count+1; end if;
 end loop;
 return v_count;
end;
$$;

create or replace function public.arena_refresh_my_deadlines()
returns integer language sql security invoker
set search_path=pg_catalog,public,private as $$
 select private.arena_refresh_my_deadlines();
$$;
revoke all on function private.arena_finalize_due_series(uuid),
 private.arena_finalize_due_all(),private.arena_refresh_my_deadlines()
 from public,anon;
revoke all on function public.arena_refresh_my_deadlines() from public,anon;
grant execute on function private.arena_refresh_my_deadlines(),
 public.arena_refresh_my_deadlines() to authenticated;
-- Scheduled backend invocation is intentionally trusted; no public access.
grant execute on function private.arena_finalize_due_all() to postgres;
