-- Protect against the same workout appearing with *different* HealthKit
-- and device UUIDs. Accepted clients still need to use the consent-based RPC.
-- Source spoofing remains possible; this guard only blocks near-duplicate
-- activity spans for the same athlete in one series.
create or replace function private.arena_prevent_mirrored_evidence()
returns trigger language plpgsql security invoker
set search_path=pg_catalog,public,private
as $$
begin
  -- Serialize competing submissions by this athlete to avoid races between
  -- two devices linking mirrored copies at the same moment.
  perform pg_advisory_xact_lock(
    hashtextextended('arena-evidence:' || new.series_id::text || ':' ||
      new.user_id::text, 0)
  );

  if exists (
    select 1 from public.arena_workout_evidence e
    where e.series_id = new.series_id
      and e.user_id = new.user_id
      and e.activity_type = new.activity_type
      and abs(extract(epoch from (e.started_at - new.started_at))) <= 90
      and abs(extract(epoch from (e.ended_at - new.ended_at))) <= 90
      and (
        (e.reported_distance_meters is null and new.reported_distance_meters is null)
        or (
          e.reported_distance_meters is not null
          and new.reported_distance_meters is not null
          and abs(e.reported_distance_meters - new.reported_distance_meters)
            <= greatest(
              100,
              greatest(e.reported_distance_meters, new.reported_distance_meters) * 0.03
            )
        )
      )
  ) then
    raise exception using
      errcode = '23505',
      message = 'This workout is already linked through another device or source';
  end if;
  return new;
end;
$$;

revoke all on function private.arena_prevent_mirrored_evidence()
 from public,anon,authenticated;

drop trigger if exists arena_prevent_mirrored_evidence_insert
 on public.arena_workout_evidence;
create trigger arena_prevent_mirrored_evidence_insert
 before insert on public.arena_workout_evidence
 for each row
 execute function private.arena_prevent_mirrored_evidence();
