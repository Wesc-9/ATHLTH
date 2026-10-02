create or replace function public.is_username_available(candidate text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  actor uuid := auth.uid();
  cleaned text := lower(trim(candidate));
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if cleaned is null
     or char_length(cleaned) < 3
     or char_length(cleaned) > 30
     or cleaned !~ '^[a-z0-9_.]+$' then
    return false;
  end if;

  return not exists (
    select 1
    from public.profiles p
    where lower(p.username) = cleaned
      and p.id <> actor
  );
end;
$$;

revoke all on function public.is_username_available(text)
  from public, anon;
grant execute on function public.is_username_available(text)
  to authenticated;
