-- Keep official Weekly Challenges continuously populated one year ahead.
-- The rotation is deterministic by ISO week, so the same weekly themes repeat every year.
-- Manually/AI-created challenges always win: the filler only inserts into empty weekly slots.

alter table public.official_weekly_challenges
  drop constraint if exists official_weekly_challenges_source_check;

alter table public.official_weekly_challenges
  add constraint official_weekly_challenges_source_check
  check (source in ('manual', 'ai', 'template', 'rotation'));

create or replace function public.ensure_official_weekly_challenge_horizon(
  p_weeks_ahead integer default 52
)
returns integer
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_first_week date;
  v_week_start date;
  v_week_end date;
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_week_number integer;
  v_slot integer;
  v_title text;
  v_subtitle text;
  v_kind text;
  v_target double precision;
  v_palette text;
  v_scene text;
  v_light text;
  v_energy text;
  v_variant integer;
  v_hero text;
  v_inserted integer := 0;
begin
  if p_weeks_ahead < 4 or p_weeks_ahead > 52 then
    raise exception 'p_weeks_ahead must be between 4 and 52';
  end if;

  -- Prevent two simultaneous app refreshes from creating the same slots.
  perform pg_advisory_xact_lock(
    hashtext('athlth_official_weekly_challenge_horizon')
  );

  v_first_week :=
    date_trunc(
      'week',
      timezone('Europe/Oslo', now())
    )::date;

  for v_slot in 0..p_weeks_ahead loop
    v_week_start := v_first_week + (v_slot * 7);
    v_week_end := v_week_start + 7;

    v_start_at :=
      (v_week_start::timestamp at time zone 'Europe/Oslo');
    v_end_at :=
      (v_week_end::timestamp at time zone 'Europe/Oslo');

    -- Preserve anything already planned for this weekly slot.
    if exists (
      select 1
      from public.official_weekly_challenges c
      where c.starts_at < v_end_at
        and c.ends_at > v_start_at
    ) then
      continue;
    end if;

    v_week_number :=
      extract(week from v_week_start)::integer;

    -- Fixed-date special weeks. These are selected by the date contained
    -- inside the Monday-Sunday window, so they stay relevant each year.
    if exists (
      select 1
      from generate_series(
        v_week_start,
        v_week_end - 1,
        interval '1 day'
      ) d
      where to_char(d, 'MM-DD') = '01-01'
    ) then
      v_title := 'New Year Kickoff';
      v_subtitle := 'Start the year strong with a fresh week of movement.';
      v_kind := 'distance';
      v_target := 25;
    elsif exists (
      select 1
      from generate_series(
        v_week_start,
        v_week_end - 1,
        interval '1 day'
      ) d
      where to_char(d, 'MM-DD') = '02-14'
    ) then
      v_title := 'Heart Run';
      v_subtitle := 'Collect a week of heart-healthy kilometres.';
      v_kind := 'distance';
      v_target := 21;
    elsif exists (
      select 1
      from generate_series(
        v_week_start,
        v_week_end - 1,
        interval '1 day'
      ) d
      where to_char(d, 'MM-DD') = '05-17'
    ) then
      v_title := '17. mai Miles';
      v_subtitle := 'Celebrate Norway with a festive week of movement.';
      v_kind := 'distance';
      v_target := 17;
    elsif exists (
      select 1
      from generate_series(
        v_week_start,
        v_week_end - 1,
        interval '1 day'
      ) d
      where to_char(d, 'MM-DD') = '10-31'
    ) then
      v_title := 'Halloween Night Run';
      v_subtitle := 'A spooky week of running and walking before the final bell.';
      v_kind := 'distance';
      v_target := 31;
    elsif exists (
      select 1
      from generate_series(
        v_week_start,
        v_week_end - 1,
        interval '1 day'
      ) d
      where to_char(d, 'MM-DD') = '12-24'
    ) then
      v_title := 'Christmas Run';
      v_subtitle := 'Move through Christmas week at your own pace.';
      v_kind := 'distance';
      v_target := 24;
    elsif exists (
      select 1
      from generate_series(
        v_week_start,
        v_week_end - 1,
        interval '1 day'
      ) d
      where to_char(d, 'MM-DD') = '12-31'
    ) then
      v_title := 'Finish Strong';
      v_subtitle := 'Close the year with one final push.';
      v_kind := 'distance';
      v_target := 50;
    else
      -- A varied 16-week core rotation, anchored to ISO week number.
      -- Because it is derived from the calendar week, it repeats every year.
      case mod(v_week_number - 1, 16)
        when 0 then
          v_title := 'Distance Builder';
          v_subtitle := 'Build your week one kilometre at a time.';
          v_kind := 'distance';
          v_target := 25;
        when 1 then
          v_title := 'Consistency Four';
          v_subtitle := 'Complete four run or walk sessions this week.';
          v_kind := 'sessions';
          v_target := 4;
        when 2 then
          v_title := 'Time on Feet';
          v_subtitle := 'Collect three hours of running or walking this week.';
          v_kind := 'minutes';
          v_target := 180;
        when 3 then
          v_title := 'Five-Day Flow';
          v_subtitle := 'Move on five different days and keep the rhythm alive.';
          v_kind := 'streak';
          v_target := 5;
        when 4 then
          v_title := 'Long Week';
          v_subtitle := 'Stack steady kilometres across the whole week.';
          v_kind := 'distance';
          v_target := 35;
        when 5 then
          v_title := 'Easy Volume';
          v_subtitle := 'Add up 150 minutes at your own pace.';
          v_kind := 'minutes';
          v_target := 150;
        when 6 then
          v_title := 'Four Corners';
          v_subtitle := 'Four sessions. Any mix of running and walking.';
          v_kind := 'sessions';
          v_target := 4;
        when 7 then
          v_title := '30K Week';
          v_subtitle := 'Reach 30 kilometres before the week is done.';
          v_kind := 'distance';
          v_target := 30;
        when 8 then
          v_title := 'Momentum Streak';
          v_subtitle := 'Build momentum with activity on four different days.';
          v_kind := 'streak';
          v_target := 4;
        when 9 then
          v_title := 'Endurance Minutes';
          v_subtitle := 'Collect four hours of run or walk time this week.';
          v_kind := 'minutes';
          v_target := 240;
        when 10 then
          v_title := 'Weekend Plus';
          v_subtitle := 'Build a balanced week and finish with 28 kilometres.';
          v_kind := 'distance';
          v_target := 28;
        when 11 then
          v_title := 'Run/Walk Five';
          v_subtitle := 'Complete five qualifying sessions this week.';
          v_kind := 'sessions';
          v_target := 5;
        when 12 then
          v_title := 'Progressive 40';
          v_subtitle := 'Work toward 40 kilometres across seven days.';
          v_kind := 'distance';
          v_target := 40;
        when 13 then
          v_title := 'Active 210';
          v_subtitle := 'Reach 210 minutes of running or walking.';
          v_kind := 'minutes';
          v_target := 210;
        when 14 then
          v_title := 'Weekly Spark';
          v_subtitle := 'Move on five days and keep your weekly spark going.';
          v_kind := 'streak';
          v_target := 5;
        else
          v_title := 'Community 32';
          v_subtitle := 'Join the community and collect 32 kilometres this week.';
          v_kind := 'distance';
          v_target := 32;
      end case;
    end if;

    -- Deterministic lightweight cover recipe; no AI image generation is
    -- required for the 53 scheduled rows.
    v_palette :=
      case mod(v_week_number, 4)
        when 0 then 'sage'
        when 1 then 'amber'
        when 2 then 'blue'
        else 'violet'
      end;
    v_scene :=
      case mod(v_week_number, 3)
        when 0 then 'mountain'
        when 1 then 'city'
        else 'coast'
      end;
    v_light :=
      case mod(v_week_number, 3)
        when 0 then 'sunrise'
        when 1 then 'daylight'
        else 'golden-hour'
      end;
    v_energy :=
      case v_kind
        when 'streak' then 'bright'
        when 'sessions' then 'steady'
        when 'minutes' then 'endurance'
        else 'forward'
      end;
    v_variant := mod(v_week_number, 4) + 1;

    v_hero := format(
      'athlth-cover://v1?palette=%s&scene=%s&light=%s&motif=route&energy=%s&variant=%s',
      v_palette,
      v_scene,
      v_light,
      v_energy,
      v_variant
    );

    insert into public.official_weekly_challenges (
      id,
      title,
      subtitle,
      kind,
      target_value,
      starts_at,
      ends_at,
      hero_asset,
      source,
      created_by,
      created_at,
      updated_at
    )
    values (
      gen_random_uuid(),
      v_title,
      v_subtitle,
      v_kind,
      v_target,
      v_start_at,
      v_end_at,
      v_hero,
      'rotation',
      null,
      now(),
      now()
    );

    v_inserted := v_inserted + 1;
  end loop;

  return v_inserted;
end;
$$;

revoke all on function public.ensure_official_weekly_challenge_horizon(integer)
from public, anon;

grant execute on function public.ensure_official_weekly_challenge_horizon(integer)
to authenticated;

comment on function public.ensure_official_weekly_challenge_horizon(integer) is
  'Idempotently fills empty official Weekly Challenge slots from the current Oslo week through the requested horizon. Manual and AI slots are preserved.';

