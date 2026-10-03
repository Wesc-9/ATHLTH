-- Allow Club managers to replace existing Club images with Storage upsert.
-- Supabase Storage upsert requires SELECT in addition to INSERT/UPDATE
-- when an object with the same path already exists.

drop policy if exists community_group_images_select_managers
on storage.objects;

create policy community_group_images_select_managers
on storage.objects
for select
to authenticated
using (
  bucket_id = 'community-group-images'
  and private.can_manage_community_group(
    ((storage.foldername(name))[1])::uuid
  )
);
