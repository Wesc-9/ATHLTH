-- Workout photos attached to completed ATHLTH sessions.
-- The first version is intentionally owner-scoped; public/friend profile
-- visibility can be widened later through the social privacy layer.

create table if not exists public.workout_media (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    workout_id uuid not null,
    image_url text not null,
    storage_path text not null unique,
    caption text,
    created_at timestamptz not null default now()
);

create index if not exists workout_media_user_created_idx
    on public.workout_media (user_id, created_at desc);

create index if not exists workout_media_workout_idx
    on public.workout_media (workout_id, created_at asc);

alter table public.workout_media enable row level security;

drop policy if exists "workout media owner read" on public.workout_media;
create policy "workout media owner read"
    on public.workout_media
    for select
    to authenticated
    using (user_id = auth.uid());

drop policy if exists "workout media owner insert" on public.workout_media;
create policy "workout media owner insert"
    on public.workout_media
    for insert
    to authenticated
    with check (user_id = auth.uid());

drop policy if exists "workout media owner update" on public.workout_media;
create policy "workout media owner update"
    on public.workout_media
    for update
    to authenticated
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

drop policy if exists "workout media owner delete" on public.workout_media;
create policy "workout media owner delete"
    on public.workout_media
    for delete
    to authenticated
    using (user_id = auth.uid());

insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
values (
    'workout-media',
    'workout-media',
    true,
    10485760,
    array['image/jpeg']::text[]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "workout media storage insert" on storage.objects;
create policy "workout media storage insert"
    on storage.objects
    for insert
    to authenticated
    with check (
        bucket_id = 'workout-media'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "workout media storage update" on storage.objects;
create policy "workout media storage update"
    on storage.objects
    for update
    to authenticated
    using (
        bucket_id = 'workout-media'
        and (storage.foldername(name))[1] = auth.uid()::text
    )
    with check (
        bucket_id = 'workout-media'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "workout media storage delete" on storage.objects;
create policy "workout media storage delete"
    on storage.objects
    for delete
    to authenticated
    using (
        bucket_id = 'workout-media'
        and (storage.foldername(name))[1] = auth.uid()::text
    );
