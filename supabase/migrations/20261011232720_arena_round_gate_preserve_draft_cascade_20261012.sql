-- Preserve cascading draft deletion while retaining the start/round lock.
-- PostgreSQL removes the parent row before ON DELETE CASCADE reaches rounds.
create or replace function private.arena_lock_round_edits_before_write()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_series_id uuid;
  v_status text;
  v_round_count integer;
begin
  if tg_op = 'DELETE' then
    v_series_id := old.series_id;
  else
    v_series_id := new.series_id;
  end if;

  if tg_op = 'UPDATE' and new.series_id is distinct from old.series_id then
    raise exception 'Arena rounds cannot be moved between competitions';
  end if;

  select s.status into v_status
  from public.arena_series s
  where s.id = v_series_id
  for update;

  if not found then
    -- Allowed only for a cascading deletion whose parent has already
    -- disappeared. Direct edits to a missing parent remain invalid.
    if tg_op = 'DELETE' then
      return old;
    end if;
    raise exception 'Arena competition no longer exists';
  end if;

  if v_status <> 'draft' then
    raise exception 'Arena rounds are locked once the competition starts';
  end if;

  if tg_op = 'INSERT' then
    select count(*) into v_round_count
    from public.arena_round_proposals r
    where r.series_id = v_series_id;
    if v_round_count >= 16 then
      raise exception 'An Arena competition can have at most 16 rounds';
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;
revoke all on function private.arena_lock_round_edits_before_write() from public;
