-- Enforce a 30-day username change cooldown at the database boundary.
-- The initial username assignment is not a change.
alter table public.profiles
  add column if not exists username_changed_at timestamptz;

create or replace function public.athlth_enforce_username_cooldown()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.username is distinct from old.username then
    if old.username_changed_at is not null
       and old.username_changed_at > now() - interval '30 days' then
      raise exception 'Brukernavn kan bare endres én gang hver 30. dag.'
        using errcode = 'P0001';
    end if;
    new.username_changed_at := now();
  else
    -- Clients cannot reset the cooldown timestamp.
    new.username_changed_at := old.username_changed_at;
  end if;
  return new;
end;
$$;

drop trigger if exists athlth_username_cooldown on public.profiles;
create trigger athlth_username_cooldown
before update on public.profiles
for each row execute function public.athlth_enforce_username_cooldown();
