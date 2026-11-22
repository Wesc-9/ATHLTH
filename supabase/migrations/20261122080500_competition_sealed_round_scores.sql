-- The source table must never expose partial round scores through Data API.
-- The purpose-built RPC returns the match status but seals other people's
-- scores until every pairing in that round/group is confirmed.
revoke select on public.athlth_tournament_matches from authenticated;
grant select(id,tournament_id,phase,round_number,group_index,slot_index,
  home_id,away_id,status,scheduled_at,deadline_at,confirmed_at)
on public.athlth_tournament_matches to authenticated;

create or replace function public.athlth_tournament_visible_matches(
 p_tournament uuid
) returns table (
 id uuid,tournament_id uuid,phase text,round_number integer,
 group_index integer,slot_index integer,home_id uuid,away_id uuid,
 home_score numeric,away_score numeric,status text,
 proposed_by uuid,confirmed_by uuid,confirmed_at timestamptz,
 evidence_note text,scheduled_at timestamptz,deadline_at timestamptz
) language plpgsql security definer stable set search_path='' as $f$
begin
 if auth.uid() is null or
    not private.athlth_tournament_can_view(p_tournament) then
    raise exception 'Competition is not accessible';
 end if;
 return query
 select m.id,m.tournament_id,m.phase,m.round_number,
        m.group_index,m.slot_index,m.home_id,m.away_id,
        case when t.format not in ('league','groups')
          or not t.competition_settings_applied or t.status='completed'
          or auth.uid() in (m.home_id,m.away_id)
          or auth.uid()=t.owner_id
          or not exists(select 1 from public.athlth_tournament_matches unresolved
            where unresolved.tournament_id=m.tournament_id
              and unresolved.phase=m.phase
              and unresolved.round_number=m.round_number
              and unresolved.group_index is not distinct from m.group_index
              and unresolved.away_id is not null
              and unresolved.status<>'confirmed'
          ) then m.home_score else null end,
        case when t.format not in ('league','groups')
          or not t.competition_settings_applied or t.status='completed'
          or auth.uid() in (m.home_id,m.away_id)
          or auth.uid()=t.owner_id
          or not exists(select 1 from public.athlth_tournament_matches unresolved
            where unresolved.tournament_id=m.tournament_id
              and unresolved.phase=m.phase
              and unresolved.round_number=m.round_number
              and unresolved.group_index is not distinct from m.group_index
              and unresolved.away_id is not null
              and unresolved.status<>'confirmed'
          ) then m.away_score else null end,
        m.status,
        case when auth.uid() in (m.home_id,m.away_id)
                 or auth.uid()=t.owner_id then m.proposed_by
             else null end,
        case when auth.uid() in (m.home_id,m.away_id)
                 or auth.uid()=t.owner_id then m.confirmed_by
             else null end,
        m.confirmed_at,
        case when auth.uid() in (m.home_id,m.away_id)
                 or auth.uid()=t.owner_id
                 or t.status='completed'
                 or t.format not in ('league','groups')
                 or not t.competition_settings_applied
                 or not exists(select 1 from public.athlth_tournament_matches unresolved
                     where unresolved.tournament_id=m.tournament_id
                       and unresolved.phase=m.phase
                       and unresolved.round_number=m.round_number
                       and unresolved.group_index is not distinct from m.group_index
                       and unresolved.away_id is not null
                       and unresolved.status<>'confirmed'
                   ) then m.evidence_note else '' end,
        m.scheduled_at,m.deadline_at
 from public.athlth_tournament_matches m
 join public.athlth_tournaments t on t.id=m.tournament_id
 where m.tournament_id=p_tournament
 order by m.round_number,m.group_index nulls first,m.slot_index,m.id;
end;
$f$;
revoke all on function public.athlth_tournament_visible_matches(uuid)
from public,anon;
grant execute on function public.athlth_tournament_visible_matches(uuid)
to authenticated;