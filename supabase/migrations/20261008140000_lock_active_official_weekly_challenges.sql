-- Freeze official Weekly Challenges once they are live.
-- Active rows may still be read and their participant progress may update,
-- but the challenge definition itself cannot be edited or deleted until it ends.

create or replace function private.prevent_active_official_weekly_challenge_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.starts_at <= now() and old.ends_at > now() then
    raise exception 'Active official weekly challenge is locked';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

revoke all on function private.prevent_active_official_weekly_challenge_change()
from public;

drop trigger if exists official_weekly_challenges_lock_active
  on public.official_weekly_challenges;

create trigger official_weekly_challenges_lock_active
before update or delete
on public.official_weekly_challenges
for each row
execute function private.prevent_active_official_weekly_challenge_change();
