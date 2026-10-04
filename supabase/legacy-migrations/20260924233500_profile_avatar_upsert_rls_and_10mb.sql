-- Fix profile avatar upserts and raise the avatar upload limit to 10 MiB.
-- Supabase Storage upserts require SELECT in addition to INSERT/UPDATE because
-- the Storage API returns the affected object row after the write.

update storage.buckets
set
  file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg','image/png','image/heic','image/heif']
where id = 'profile-avatars';

drop policy if exists profile_avatars_select_own
  on storage.objects;

create policy profile_avatars_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
