-- Public exercise marketplace: any custom exercise may share a name with
-- another custom exercise. Only names in ATHLTH's standard library are reserved.
-- Users cannot reassign ownership or falsify the original author on publication.
create table if not exists public.exercise_marketplace (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references auth.users(id) on delete cascade,
  creator_username text not null,
  exercise_name text not null check (char_length(btrim(exercise_name)) between 3 and 100),
  name_key text generated always as
    (lower(regexp_replace(btrim(exercise_name), '[[:space:]]+', ' ', 'g'))) stored,
  instructions text[] not null default '{}'::text[],
  primary_muscles text[] not null default '{}'::text[],
  secondary_muscles text[] not null default '{}'::text[],
  equipment text[] not null default '{}'::text[],
  created_at timestamptz not null default now()
);
alter table public.exercise_marketplace drop constraint if exists exercise_marketplace_name_key_unique;
create index if not exists exercise_marketplace_name_lookup_idx
    on public.exercise_marketplace(name_key);
create index if not exists exercise_marketplace_recent_idx
    on public.exercise_marketplace(created_at desc);
create index if not exists exercise_marketplace_creator_idx
    on public.exercise_marketplace(creator_id);

alter table public.exercise_marketplace enable row level security;
revoke all on public.exercise_marketplace from anon, authenticated;
grant select, insert, delete on public.exercise_marketplace to authenticated;

drop policy if exists exercise_marketplace_list_public on public.exercise_marketplace;
create policy exercise_marketplace_list_public on public.exercise_marketplace
  for select to authenticated using (true);
drop policy if exists exercise_marketplace_creator_publish on public.exercise_marketplace;
create policy exercise_marketplace_creator_publish on public.exercise_marketplace
  for insert to authenticated with check (creator_id = (select auth.uid()));
drop policy if exists exercise_marketplace_creator_remove on public.exercise_marketplace;
create policy exercise_marketplace_creator_remove on public.exercise_marketplace
  for delete to authenticated using (creator_id = (select auth.uid()));

create or replace function public.validate_exercise_marketplace_insert()
returns trigger language plpgsql security invoker set search_path = ''
as $$
declare canonical_username text;
begin
  if new.creator_id is distinct from auth.uid() then
    raise exception 'Only the authenticated creator may publish' using errcode = '42501';
  end if;
  select p.username into canonical_username
    from public.profiles p where p.id = new.creator_id;
  if canonical_username is null or length(btrim(canonical_username)) = 0 then
    raise exception 'Creator username required' using errcode = '23514';
  end if;
  new.creator_username := btrim(canonical_username);
  if exists (
    select 1 from public.exercise_catalog c
    where c.is_published = true
      and lower(regexp_replace(btrim(c.name), '[[:space:]]+', ' ', 'g')) =
          lower(regexp_replace(btrim(new.exercise_name), '[[:space:]]+', ' ', 'g'))
  ) then
    raise exception 'Exercise name reserved by ATHLTH library' using errcode = '23505';
  end if;
  return new;
end $$;
revoke all on function public.validate_exercise_marketplace_insert()
  from public, anon, authenticated;
drop trigger if exists validate_exercise_marketplace_insert_trigger
  on public.exercise_marketplace;
create trigger validate_exercise_marketplace_insert_trigger
  before insert on public.exercise_marketplace
  for each row execute function public.validate_exercise_marketplace_insert();
