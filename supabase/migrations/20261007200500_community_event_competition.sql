-- Optional competition mode for Community events.
-- An event is a one-time, check-in based competition. Challenges remain
-- asynchronous / multi-day competition surfaces.

alter table public.community_events
  add column if not exists competition_enabled boolean not null default false,
  add column if not exists competition_metric text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'community_events_competition_metric_check'
      and conrelid = 'public.community_events'::regclass
  ) then
    alter table public.community_events
      add constraint community_events_competition_metric_check
      check (
        (
          competition_enabled = false
          and competition_metric is null
        )
        or
        (
          competition_enabled = true
          and competition_metric in (
            'fastest_time',
            'highest_weight',
            'most_reps',
            'points'
          )
        )
      );
  end if;
end
$$;

alter table public.community_event_participants
  add column if not exists competition_result_value double precision,
  add column if not exists competition_result_submitted_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'community_event_competition_result_value_check'
      and conrelid = 'public.community_event_participants'::regclass
  ) then
    alter table public.community_event_participants
      add constraint community_event_competition_result_value_check
      check (
        competition_result_value is null
        or (
          isfinite(competition_result_value)
          and competition_result_value > 0
        )
      );
  end if;
end
$$;

create or replace function public.community_event_validate_competition_result()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  target_event public.community_events%rowtype;
begin
  if new.attendance_status <> 'going' then
    new.competition_result_value := null;
    new.competition_result_submitted_at := null;
    return new;
  end if;

  if new.competition_result_value is not distinct from old.competition_result_value then
    return new;
  end if;

  if new.competition_result_value is null then
    new.competition_result_submitted_at := null;
    return new;
  end if;

  select *
    into target_event
    from public.community_events
   where id = new.event_id;

  if target_event.id is null
     or target_event.competition_enabled is not true
     or target_event.competition_metric is null then
    raise exception 'Event competition is not enabled.';
  end if;

  if now() < target_event.starts_at then
    raise exception 'Competition results can only be submitted after the event starts.';
  end if;

  if new.checked_in_at is null then
    raise exception 'Check in before submitting a competition result.';
  end if;

  new.competition_result_submitted_at := now();
  return new;
end;
$$;

drop trigger if exists community_event_competition_result_trigger
  on public.community_event_participants;

create trigger community_event_competition_result_trigger
before update of attendance_status, competition_result_value
on public.community_event_participants
for each row
execute function public.community_event_validate_competition_result();

revoke update on table public.community_event_participants
  from authenticated;

grant update (
  attendance_status,
  check_in_method,
  competition_result_value
)
on table public.community_event_participants
to authenticated;

create index if not exists community_event_competition_results_idx
  on public.community_event_participants (
    event_id,
    competition_result_value
  )
  where competition_result_value is not null;
