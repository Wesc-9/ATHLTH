-- Public profile header + moderation audit for user-provided public images.

alter table public.profiles
  add column if not exists header_artwork_name text,
  add column if not exists header_image_url text;

alter table public.social_profile_cards
  add column if not exists header_artwork_name text,
  add column if not exists header_image_url text;

create or replace function private.sync_social_profile()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  insert into public.profile_social_settings (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.social_profile_cards (
    user_id,
    username,
    display_name,
    bio,
    avatar_url,
    header_artwork_name,
    header_image_url,
    created_at,
    updated_at
  )
  values (
    new.id,
    new.username,
    new.display_name,
    new.bio,
    new.avatar_url,
    new.header_artwork_name,
    new.header_image_url,
    coalesce(new.created_at, now()),
    coalesce(new.updated_at, now())
  )
  on conflict (user_id) do update
  set username = excluded.username,
      display_name = excluded.display_name,
      bio = excluded.bio,
      avatar_url = excluded.avatar_url,
      header_artwork_name = excluded.header_artwork_name,
      header_image_url = excluded.header_image_url,
      updated_at = excluded.updated_at;

  return new;
end;
$$;

update public.social_profile_cards c
set header_artwork_name = p.header_artwork_name,
    header_image_url = p.header_image_url
from public.profiles p
where p.id = c.user_id;

create table if not exists public.public_media_moderation_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  purpose text not null,
  entity_id text,
  image_hash text not null,
  decision text not null check (decision in ('approved','rejected','review','unavailable')),
  provider text not null,
  categories jsonb not null default '[]'::jsonb,
  reason text,
  created_at timestamptz not null default now()
);

alter table public.public_media_moderation_events enable row level security;

create index if not exists public_media_moderation_user_created_idx
  on public.public_media_moderation_events (user_id, created_at desc);

create index if not exists public_media_moderation_hash_idx
  on public.public_media_moderation_events (user_id, image_hash, decision, created_at desc);

comment on table public.public_media_moderation_events is
  'Server-only audit log for user images checked before public publication.';
