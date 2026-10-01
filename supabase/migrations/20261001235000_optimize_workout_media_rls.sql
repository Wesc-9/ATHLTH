drop policy if exists "workout media owner read" on public.workout_media;
create policy "workout media owner read"
    on public.workout_media
    for select
    to authenticated
    using (user_id = (select auth.uid()));

drop policy if exists "workout media owner insert" on public.workout_media;
create policy "workout media owner insert"
    on public.workout_media
    for insert
    to authenticated
    with check (user_id = (select auth.uid()));

drop policy if exists "workout media owner update" on public.workout_media;
create policy "workout media owner update"
    on public.workout_media
    for update
    to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

drop policy if exists "workout media owner delete" on public.workout_media;
create policy "workout media owner delete"
    on public.workout_media
    for delete
    to authenticated
    using (user_id = (select auth.uid()));

drop policy if exists "workout media storage insert" on storage.objects;
create policy "workout media storage insert"
    on storage.objects
    for insert
    to authenticated
    with check (
        bucket_id = 'workout-media'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

drop policy if exists "workout media storage update" on storage.objects;
create policy "workout media storage update"
    on storage.objects
    for update
    to authenticated
    using (
        bucket_id = 'workout-media'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    )
    with check (
        bucket_id = 'workout-media'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

drop policy if exists "workout media storage delete" on storage.objects;
create policy "workout media storage delete"
    on storage.objects
    for delete
    to authenticated
    using (
        bucket_id = 'workout-media'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );