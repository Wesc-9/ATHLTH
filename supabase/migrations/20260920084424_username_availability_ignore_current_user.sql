create or replace function public.is_username_available(candidate text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    candidate is not null
    and char_length(candidate) between 3 and 20
    and candidate ~ '^[a-z0-9_]+$'
    and lower(candidate) <> all (array['admin','support','athlth','official','training'])
    and not exists (
      select 1
      from public.profiles p
      where p.username = candidate::extensions.citext
        and ((select auth.uid()) is null or p.id <> (select auth.uid()))
    );
$$;

revoke execute on function public.is_username_available(text) from public;
grant execute on function public.is_username_available(text) to anon, authenticated;
