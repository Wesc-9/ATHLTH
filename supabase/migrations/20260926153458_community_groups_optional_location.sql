alter table public.community_groups
  alter column location_name set default '';

alter table public.community_groups
  drop constraint if exists community_groups_location_name_check;

alter table public.community_groups
  add constraint community_groups_location_name_check
  check (
    char_length(trim(location_name)) <= 120
  );
