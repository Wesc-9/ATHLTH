-- ATHLTH Arena v1.7.2: locked series, participant-approved results,
-- and atomic scoreboard. Manual results are group-verified, never mislabeled
-- as GPS/HealthKit verified.
alter table public.arena_series drop constraint if exists arena_series_status_check1;
alter table public.arena_series
  add column if not exists starts_at timestamptz,
  add column if not exists ends_at timestamptz,
  add column if not exists completed_at timestamptz;
alter table public.arena_series
  drop constraint if exists arena_series_status_check;
alter table public.arena_series
  add constraint arena_series_status_check
  check(status in ('draft','active','completed','cancelled'));

create table if not exists public.arena_round_results (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.arena_series(id) on delete cascade,
  round_id uuid not null references public.arena_round_proposals(id) on delete cascade,
  proposed_by uuid references public.profiles(id) on delete set null,
  ranked_slots uuid[] not null check(cardinality(ranked_slots) between 1 and 3),
  evidence_note text not null check(char_length(btrim(evidence_note)) between 1 and 600),
  verification text not null default 'group_consensus'
    check(verification='group_consensus'),
  status text not null default 'pending'
    check(status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
create unique index if not exists arena_results_one_active_round
  on public.arena_round_results(round_id)
  where status in ('pending','approved');
create index if not exists arena_results_series_idx
  on public.arena_round_results(series_id,created_at desc);
create index if not exists arena_results_proposer_idx
  on public.arena_round_results(proposed_by,created_at desc);

create table if not exists public.arena_round_result_votes (
  result_id uuid not null references public.arena_round_results(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  accepted boolean not null,
  created_at timestamptz not null default now(),
  primary key(result_id,user_id)
);
create index if not exists arena_results_votes_actor
  on public.arena_round_result_votes(user_id,created_at desc);

create table if not exists public.arena_round_points (
  round_id uuid not null references public.arena_round_proposals(id) on delete cascade,
  slot_id uuid not null references public.arena_series_members(slot_id) on delete cascade,
  points numeric(10,2) not null check(points > 0),
  recorded_at timestamptz not null default now(),
  primary key(round_id,slot_id)
);
create index if not exists arena_round_points_slot
  on public.arena_round_points(slot_id,recorded_at desc);

alter table public.arena_round_results enable row level security;
alter table public.arena_round_result_votes enable row level security;
alter table public.arena_round_points enable row level security;
revoke all on public.arena_round_results,
  public.arena_round_result_votes,public.arena_round_points from anon,authenticated;
grant select on public.arena_round_results,
  public.arena_round_result_votes,public.arena_round_points to authenticated;
drop policy if exists arena_round_results_read on public.arena_round_results;
create policy arena_round_results_read on public.arena_round_results
 for select to authenticated using(private.arena_can_access(series_id));
drop policy if exists arena_result_votes_read on public.arena_round_result_votes;
create policy arena_result_votes_read on public.arena_round_result_votes
 for select to authenticated using(exists(
  select 1 from public.arena_round_results r where r.id=result_id
    and private.arena_can_access(r.series_id)
 ));
drop policy if exists arena_points_read on public.arena_round_points;
create policy arena_points_read on public.arena_round_points
 for select to authenticated using(exists(
  select 1 from public.arena_round_proposals r where r.id=round_id
    and private.arena_can_access(r.series_id)
 ));

-- No participant can silently change the rules after the series starts.
drop policy if exists arena_rounds_remove_unvoted on public.arena_round_proposals;
create policy arena_rounds_remove_unvoted
 on public.arena_round_proposals
 for delete to authenticated using(
  proposed_by=(select auth.uid())
  and exists(select 1 from public.arena_series s
    where s.id=series_id and s.status='draft')
  and not exists(select 1 from public.arena_round_approvals a
    where a.round_id=id)
 );

create or replace function private.arena_start_series_impl(p_series uuid)
returns text language plpgsql security definer
set search_path=pg_catalog,public,private as $$
declare v_s public.arena_series%rowtype;
v_people integer;
v_rounds integer;
begin
  select * into v_s from public.arena_series where id=p_series for update;
  if not found or v_s.status <> 'draft' then
    raise exception 'Competition is not a draft';
  end if;
  if not private.arena_is_organizer(p_series) then
    raise exception 'Only the organizer can start the competition';
  end if;
  if exists(select 1 from public.arena_series_members m
     where m.series_id=p_series and m.response <> 'accepted') then
     raise exception 'Every invited participant must accept before start';
  end if;
  select count(*) into v_people from public.arena_series_members m
    where m.series_id=p_series and m.response='accepted' and m.user_id is not null;
  if v_people < 2 then raise exception 'A series needs at least two athletes'; end if;
  if v_s.scope='duel' and v_people <> 2 then
    raise exception 'A duel requires two athletes';
  end if;
  select count(*) into v_rounds from public.arena_round_proposals r where r.series_id=p_series;
  if v_rounds < 1 then raise exception 'Add at least one round'; end if;
  if exists(
    select 1 from public.arena_round_proposals r
    cross join public.arena_series_members m
    where r.series_id=p_series and m.series_id=p_series
      and m.response='accepted' and m.user_id is not null
      and not exists(select 1 from public.arena_round_approvals a
        where a.round_id=r.id and a.user_id=m.user_id)
  ) then raise exception 'All participants must approve every round'; end if;

  update public.arena_series
  set status='active',starts_at=now(),
      ends_at=now()+make_interval(days=>v_s.duration_days)
  where id=p_series;
  return 'active';
end; $$;

create or replace function public.arena_start_series(p_series uuid)
returns text language sql security invoker
set search_path=pg_catalog,public,private
as $$select private.arena_start_series_impl(p_series);$$;

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
  if now()>v_s.ends_at+interval '14 days' then
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

create or replace function public.arena_propose_result(
 p_round uuid,p_slots uuid[],p_evidence text
) returns uuid language sql security invoker
set search_path=pg_catalog,public,private
as $$select private.arena_propose_result_impl(p_round,p_slots,p_evidence);$$;

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
  if v_round_count=v_approved_count then
     update public.arena_series
       set status='completed',completed_at=now() where id=v_s.id;
  end if;
  insert into public.social_inbox_events(
    recipient_id,kind,title,message,entity_type,entity_id,actor_id
  )
  select m.user_id,'arena_round',
    case when v_round_count=v_approved_count then 'Arena – mester kåret'
     else 'Arena – poeng oppdatert' end,
    case when v_round_count=v_approved_count then 'Konkurransen er ferdig. Se sluttstillingen.'
     else 'Et runderesultat er godkjent. Se oppdatert poengstilling.' end,
    'arena_series',v_s.id,v_actor
  from public.arena_series_members m
  where m.series_id=v_s.id and m.response='accepted' and m.user_id is not null;
  return case when v_round_count=v_approved_count then 'completed' else 'approved' end;
end; $$;

create or replace function public.arena_vote_result(
 p_result uuid,p_accept boolean
) returns text language sql security invoker
set search_path=pg_catalog,public,private
as $$select private.arena_vote_result_impl(p_result,p_accept);$$;

revoke all on function private.arena_start_series_impl(uuid),
 private.arena_propose_result_impl(uuid,uuid[],text),
 private.arena_vote_result_impl(uuid,boolean) from public,anon;
revoke all on function public.arena_start_series(uuid),
 public.arena_propose_result(uuid,uuid[],text),
 public.arena_vote_result(uuid,boolean) from public,anon;
grant execute on function private.arena_start_series_impl(uuid),
 private.arena_propose_result_impl(uuid,uuid[],text),
 private.arena_vote_result_impl(uuid,boolean) to authenticated;
grant execute on function public.arena_start_series(uuid),
 public.arena_propose_result(uuid,uuid[],text),
 public.arena_vote_result(uuid,boolean) to authenticated;
