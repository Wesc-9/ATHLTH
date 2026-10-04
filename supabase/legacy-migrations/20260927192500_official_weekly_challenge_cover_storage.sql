insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'official-weekly-challenge-covers',
  'official-weekly-challenge-covers',
  true,
  8388608,
  array['image/png','image/jpeg','image/webp']::text[]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

alter table public.official_weekly_challenges
  alter column hero_asset set default '';

update public.official_weekly_challenges
set hero_asset = '',
    updated_at = now()
where hero_asset = 'CommunityHero';