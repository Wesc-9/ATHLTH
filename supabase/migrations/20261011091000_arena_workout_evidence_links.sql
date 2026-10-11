-- Evidence suggestions sourced from workout histories.
-- Athlete explicitly selects and shares limited metrics; do NOT describe
-- these records as cryptographically verified HealthKit/GPS evidence.
create table if not exists public.arena_workout_evidence(
 id uuid primary key default gen_random_uuid(),
 series_id uuid not null references public.arena_series(id) on delete cascade,
 round_id uuid not null references public.arena_round_proposals(id) on delete cascade,
 slot_id uuid not null references public.arena_series_members(slot_id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 source_workout_id uuid not null,
 source text not null check(source in ('iphone','athlth_strength','apple_health')),
 activity_type text not null check(activity_type in ('running','walking','strength')),
 started_at timestamptz not null,
 ended_at timestamptz not null,
 metric_type text not null check(metric_type in ('elapsed_seconds','distance_meters','completed_workout')),
 metric_value numeric(12,3) not null check(metric_value>0 and metric_value<1000000000),
 submitted_at timestamptz not null default now(),
 check(ended_at>started_at),
 check(ended_at-started_at<interval '24 hours')
);
-- Across all rounds in the same series, one activity contributes only once.
create unique index if not exists arena_workout_source_one_use
 on public.arena_workout_evidence(series_id,user_id,source_workout_id);
create index if not exists arena_evidence_round_idx
 on public.arena_workout_evidence(round_id,submitted_at desc);
create index if not exists arena_evidence_slot_idx
 on public.arena_workout_evidence(slot_id);
create index if not exists arena_evidence_owner_idx
 on public.arena_workout_evidence(user_id);

alter table public.arena_workout_evidence enable row level security;
revoke all on public.arena_workout_evidence from anon,authenticated;
grant select on public.arena_workout_evidence to authenticated;
drop policy if exists arena_evidence_read on public.arena_workout_evidence;
create policy arena_evidence_read on public.arena_workout_evidence
 for select to authenticated using(private.arena_can_access(series_id));

create or replace function private.arena_share_evidence_impl(
 p_round uuid,p_source_workout uuid,p_source text,p_activity text,
 p_started timestamptz,p_ended timestamptz,p_metric_type text,p_metric numeric
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_series public.arena_series%rowtype;
v_round public.arena_round_proposals%rowtype;
v_slot uuid;
v_actor uuid:=(select auth.uid());
v_id uuid;
begin
 if v_actor is null then raise exception 'Sign in required'; end if;
 select * into v_round from public.arena_round_proposals
  where id=p_round;
 if not found then raise exception 'Unknown round'; end if;
 select * into v_series from public.arena_series
  where id=v_round.series_id;
 if v_series.status<>'active' then raise exception 'Series is not active'; end if;
 if p_started<v_series.starts_at or p_ended>v_series.ends_at or p_ended<=p_started
     or p_ended-p_started>interval '24 hours' then
   raise exception 'The workout must be completed within the series window';
 end if;
 select slot_id into v_slot from public.arena_series_members
  where series_id=v_series.id and user_id=v_actor and response='accepted';
 if v_slot is null then raise exception 'Only participants can share workout results'; end if;
 if p_source not in ('iphone','athlth_strength','apple_health')
   or p_activity not in ('running','walking','strength')
   or p_source_workout is null
   or p_metric is null or p_metric<=0 or p_metric>1000000000 then
   raise exception 'Invalid workout metric';
 end if;
 if v_round.template='fastest5K' then
   if p_activity<>'running' or p_metric_type<>'elapsed_seconds'
       or p_metric<150 or p_metric>18000 then
     raise exception 'A qualifying 5 km run must include an elapsed time';
   end if;
 elsif v_round.template='fastest1K' then
   if p_activity<>'running' or p_metric_type<>'elapsed_seconds'
       or p_metric<60 or p_metric>7200 then
     raise exception 'A qualifying 1 km run must include an elapsed time';
   end if;
 elsif v_round.template='mostDistance' then
   if p_activity not in ('running','walking')
       or p_metric_type<>'distance_meters' or p_metric>500000 then
     raise exception 'Only recorded walking/running distance is supported';
   end if;
 elsif v_round.template='mostWorkouts' then
   if p_metric_type<>'completed_workout' or p_metric<>1
       or p_ended-p_started<interval '10 minutes' then
     raise exception 'Completed sessions must last at least ten minutes';
   end if;
 else
   raise exception 'Exercise-specific and custom rounds need separate review';
 end if;
 -- A linked source identity comes from the athlete's client, so RLS ensures
 -- ownership of the submission, not authenticity of their workout bytes.
 insert into public.arena_workout_evidence(
  series_id,round_id,slot_id,user_id,source_workout_id,source,
  activity_type,started_at,ended_at,metric_type,metric_value)
 values(v_series.id,p_round,v_slot,v_actor,p_source_workout,p_source,
  p_activity,p_started,p_ended,p_metric_type,p_metric)
 returning id into v_id;
 return v_id;
end;
$$;
create or replace function public.arena_share_evidence(
 p_round uuid,p_source_workout uuid,p_source text,p_activity text,
 p_started timestamptz,p_ended timestamptz,p_metric_type text,p_metric numeric
) returns uuid language sql security invoker
set search_path=pg_catalog,public,private
as $$select private.arena_share_evidence_impl(
 p_round,p_source_workout,p_source,p_activity,
 p_started,p_ended,p_metric_type,p_metric
);$$;
revoke all on function public.arena_share_evidence(
 uuid,uuid,text,text,timestamptz,timestamptz,text,numeric)
 from public,anon;
revoke all on function private.arena_share_evidence_impl(
 uuid,uuid,text,text,timestamptz,timestamptz,text,numeric)
 from public,anon;
grant execute on function public.arena_share_evidence(
 uuid,uuid,text,text,timestamptz,timestamptz,text,numeric)
 to authenticated;
grant execute on function private.arena_share_evidence_impl(
 uuid,uuid,text,text,timestamptz,timestamptz,text,numeric)
 to authenticated;
