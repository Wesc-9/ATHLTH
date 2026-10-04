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
