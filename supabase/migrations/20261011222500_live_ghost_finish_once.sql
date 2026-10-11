-- Live Ghost: one finish per participant, even when iPhone/Watch emit
-- duplicate completion notifications. No ranking or Arena points are
-- awarded by this trigger; existing room sync still owns the live result.
create or replace function private.live_ghost_finish_once_guard()
returns trigger
language plpgsql
set search_path = pg_catalog, public, private
as $$
begin
  if old.finished_at is not null then
    -- First successfully recorded finish is authoritative for this race.
    -- Allow unrelated participant updates without altering the result.
    new.finished_at := old.finished_at;
    new.elapsed_seconds := old.elapsed_seconds;
    return new;
  end if;

  if new.finished_at is null and new.elapsed_seconds is not null then
    raise exception 'A Live Ghost time requires a finished_at timestamp';
  end if;

  if new.finished_at is not null then
    if new.elapsed_seconds is null
       or new.elapsed_seconds < 5
       or new.elapsed_seconds > 86400 then
      raise exception 'Invalid Live Ghost finish duration';
    end if;

    if not exists (
      select 1
      from public.live_ghost_race_rooms r
      where r.challenge_id = new.challenge_id
        and r.status in ('countdown','racing')
        and r.starts_at is not null
        and r.starts_at <= now()
    ) then
      raise exception 'Live Ghost cannot finish before synchronized start';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.live_ghost_finish_once_guard()
  from public, anon, authenticated;

drop trigger if exists live_ghost_finish_once_before_update
  on public.live_ghost_race_participants;

create trigger live_ghost_finish_once_before_update
before update on public.live_ghost_race_participants
for each row
execute function private.live_ghost_finish_once_guard();
