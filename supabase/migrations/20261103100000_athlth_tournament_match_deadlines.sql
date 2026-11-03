-- Tournament match schedule and organizer-controlled deadline extension.
-- A missed deadline is informative and never auto-awards a win or eliminates
-- an athlete. Existing active rows get explicit timestamps only if missing.
alter table public.athlth_tournaments
  add column if not exists round_days integer not null default 7
    check(round_days between 1 and 30);

alter table public.athlth_tournament_matches
  add column if not exists scheduled_at timestamptz,
  add column if not exists deadline_at timestamptz;

create or replace function private.athlth_tournament_set_match_dates()
returns trigger language plpgsql security definer
set search_path = '' as $$
declare
  v_t public.athlth_tournaments%rowtype;
  v_practices integer;
  v_round_offset integer;
  v_days integer;
begin
  select * into v_t from public.athlth_tournaments
  where id=new.tournament_id;
  if not found then raise exception 'Tournament not found'; end if;
  v_days := coalesce(v_t.round_days,7);
  select count(*) into v_practices
    from public.athlth_tournament_practice
   where tournament_id=new.tournament_id;
  if new.phase='warmup' then
     v_round_offset := new.round_number-1;
  elsif new.phase in ('cup','playoff') and new.round_number>1 then
     -- A later knockout round becomes available after all required
     -- approvals, so its deadline begins when the round is generated.
     v_round_offset := 0;
  else
     -- Official league/group/cup rounds begin after practice rounds.
     v_round_offset := greatest(0,v_practices+new.round_number-1);
  end if;
  new.scheduled_at := coalesce(new.scheduled_at,
     clock_timestamp() + (v_round_offset * v_days) * interval '1 day');
  new.deadline_at := coalesce(new.deadline_at,
     new.scheduled_at + v_days * interval '1 day');
  return new;
end;
$$;

drop trigger if exists athlth_tournament_match_dates_insert
 on public.athlth_tournament_matches;
create trigger athlth_tournament_match_dates_insert
before insert on public.athlth_tournament_matches
for each row execute function private.athlth_tournament_set_match_dates();

-- Older active tournaments, if any, retain their original match order.
-- No score, winner or point fields are touched.
update public.athlth_tournament_matches m
 set scheduled_at=coalesce(m.scheduled_at,t.started_at,t.created_at),
     deadline_at=coalesce(m.deadline_at,
         coalesce(m.scheduled_at,t.started_at,t.created_at)
         + coalesce(t.round_days,7) * interval '1 day')
from public.athlth_tournaments t
where t.id=m.tournament_id and
      (m.scheduled_at is null or m.deadline_at is null);

create or replace function public.athlth_tournament_extend_deadline(
    p_match uuid, p_deadline timestamptz
) returns void language plpgsql security definer
set search_path='' as $$
declare
    v_actor uuid := auth.uid();
    v_t public.athlth_tournaments%rowtype;
    v_m public.athlth_tournament_matches%rowtype;
begin
    if v_actor is null then raise exception 'Sign in required'; end if;
    select * into v_m from public.athlth_tournament_matches
    where id=p_match for update;
    if not found then raise exception 'Match not found'; end if;
    select * into v_t from public.athlth_tournaments
    where id=v_m.tournament_id for update;
    if v_t.owner_id<>v_actor or v_t.status<>'active' then
        raise exception 'Only the organizer can extend active matches';
    end if;
    if v_m.status='confirmed' or v_m.away_id is null then
        raise exception 'This match is already final';
    end if;
    if p_deadline is null or
       p_deadline <= greatest(clock_timestamp(),v_m.deadline_at) or
       p_deadline > clock_timestamp()+ interval '30 days' then
        raise exception 'Choose a later deadline within 30 days';
    end if;
    update public.athlth_tournament_matches
       set deadline_at=p_deadline where id=p_match;
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event,info
    ) values(v_m.tournament_id,v_actor,'deadline_extended',
        jsonb_build_object(
           'match_id',p_match,'old_deadline',v_m.deadline_at,
           'new_deadline',p_deadline
        ));
end;
$$;
revoke all on function private.athlth_tournament_set_match_dates()
 from public,anon,authenticated;
revoke all on function public.athlth_tournament_extend_deadline(
 uuid,timestamptz) from public,anon;
grant execute on function public.athlth_tournament_extend_deadline(
 uuid,timestamptz) to authenticated;
