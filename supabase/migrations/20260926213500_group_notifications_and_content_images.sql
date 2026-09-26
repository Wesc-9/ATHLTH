-- ATHLTH 1.4.1: simplify group notifications and add optional
-- cover images for group events and challenges.

update public.community_group_notification_preferences
set mode = 'all'
where mode = 'important';

alter table public.community_group_notification_preferences
  alter column mode set default 'all';

alter table public.community_group_notification_preferences
  drop constraint if exists
    community_group_notification_preferences_mode_check;

alter table public.community_group_notification_preferences
  add constraint
    community_group_notification_preferences_mode_check
  check (mode in ('all', 'muted'));

create or replace function private.community_group_notification_mode(
  p_group_id uuid,
  p_user_id uuid
)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select coalesce(
    (
      select p.mode
      from public.community_group_notification_preferences p
      where p.group_id = p_group_id
        and p.user_id = p_user_id
    ),
    'all'
  );
$$;

alter table public.community_group_events
  add column if not exists image_url text;

alter table public.community_group_challenges
  add column if not exists image_url text;

insert into storage.buckets(
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'community-content-images',
  'community-content-images',
  true,
  5242880,
  array[
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif'
  ]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists
  community_content_images_insert_creators
on storage.objects;

create policy community_content_images_insert_creators
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'community-content-images'
  and private.can_create_community_group_content(
    ((storage.foldername(name))[1])::uuid,
    (select auth.uid())
  )
);

drop policy if exists
  community_content_images_update_creators
on storage.objects;

create policy community_content_images_update_creators
on storage.objects
for update
to authenticated
using (
  bucket_id = 'community-content-images'
  and private.can_create_community_group_content(
    ((storage.foldername(name))[1])::uuid,
    (select auth.uid())
  )
)
with check (
  bucket_id = 'community-content-images'
  and private.can_create_community_group_content(
    ((storage.foldername(name))[1])::uuid,
    (select auth.uid())
  )
);

drop policy if exists
  community_content_images_delete_creators
on storage.objects;

create policy community_content_images_delete_creators
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'community-content-images'
  and private.can_create_community_group_content(
    ((storage.foldername(name))[1])::uuid,
    (select auth.uid())
  )
);

revoke all on function private.community_group_notification_mode(
  uuid,
  uuid
) from public, anon, authenticated;
