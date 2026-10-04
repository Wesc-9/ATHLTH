alter table public.community_groups
  add column if not exists header_image_url text,
  add column if not exists featured_challenge_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'community_groups_featured_challenge_id_fkey'
      and conrelid = 'public.community_groups'::regclass
  ) then
    alter table public.community_groups
      add constraint community_groups_featured_challenge_id_fkey
      foreign key (featured_challenge_id)
      references public.community_group_challenges(id)
      on delete set null;
  end if;
end
$$;

create index if not exists community_groups_featured_challenge_idx
  on public.community_groups(featured_challenge_id)
  where featured_challenge_id is not null;

create or replace function private.validate_community_group_featured_challenge()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.featured_challenge_id is not null
     and not exists (
       select 1
       from public.community_group_challenges c
       where c.id = new.featured_challenge_id
         and c.group_id = new.id
     ) then
    raise exception 'Featured challenge must belong to the same Club';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_community_group_featured_challenge
  on public.community_groups;

create trigger validate_community_group_featured_challenge
before insert or update of featured_challenge_id
on public.community_groups
for each row
execute function private.validate_community_group_featured_challenge();
