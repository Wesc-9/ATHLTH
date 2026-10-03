-- ATHLTH 1.5.9: allow authenticated owners to read/list their own
-- workout-media objects. Supabase Storage upserts need SELECT in addition
-- to INSERT/UPDATE, and event covers reuse this existing media bucket.
drop policy if exists "workout media storage select owner"
on storage.objects;

create policy "workout media storage select owner"
on storage.objects for select
to authenticated
using (
  bucket_id = 'workout-media'
  and (storage.foldername(name))[1] =
      (select auth.uid())::text
);
