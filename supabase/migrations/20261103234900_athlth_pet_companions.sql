-- ATHLTH 2.1.0: personal pets, optional public profile sharing and workout companion stats.
-- Photo bucket is PRIVATE. Users must explicitly opt in to public visibility.
create table if not exists public.profile_pets (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null check (length(btrim(name)) between 1 and 80),
    species text not null default 'dog' check (species in ('dog','cat','horse','other')),
    breed text,
    birth_date date,
    weight_kg numeric(7,2) check (weight_kg is null or (weight_kg > 0 and weight_kg <= 1000)),
    photo_path text,
    show_on_profile boolean not null default true,
    is_public boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique(user_id,id),
    constraint pet_photo_owner_path check (
        photo_path is null or photo_path like (user_id::text || '/' || id::text || '/%')
    )
);
create index if not exists profile_pets_user_idx
    on public.profile_pets(user_id,created_at);
create index if not exists profile_pets_public_idx
    on public.profile_pets(user_id) where is_public and show_on_profile;

create table if not exists public.workout_pet_usage (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    workout_id uuid not null,
    pet_id uuid not null,
    workout_title text not null default '',
    activity_type text not null,
    source text not null default '',
    started_at timestamptz not null,
    ended_at timestamptz not null,
    duration_seconds double precision not null default 0 check (duration_seconds >= 0),
    distance_meters double precision check (distance_meters is null or distance_meters >= 0),
    participation_started_at timestamptz,
    participation_ended_at timestamptz,
    distance_is_estimated boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique(user_id,workout_id,pet_id),
    foreign key (user_id,pet_id) references public.profile_pets(user_id,id) on delete cascade,
    check (ended_at >= started_at),
    check (participation_ended_at is null or participation_started_at is null or participation_ended_at >= participation_started_at)
);
create index if not exists workout_pet_usage_pet_date_idx
    on public.workout_pet_usage(user_id,pet_id,started_at desc);
create index if not exists workout_pet_usage_workout_idx
    on public.workout_pet_usage(user_id,workout_id);

alter table public.profile_pets enable row level security;
alter table public.workout_pet_usage enable row level security;
grant select,insert,update,delete on public.profile_pets to authenticated;
grant select,insert,update,delete on public.workout_pet_usage to authenticated;

drop policy if exists "pet_owner_or_shared_read" on public.profile_pets;
create policy "pet_owner_or_shared_read" on public.profile_pets
    for select to authenticated using (
        (select auth.uid())=user_id or (is_public and show_on_profile)
    );
drop policy if exists "pet_owner_insert" on public.profile_pets;
create policy "pet_owner_insert" on public.profile_pets
    for insert to authenticated with check ((select auth.uid())=user_id);
drop policy if exists "pet_owner_update" on public.profile_pets;
create policy "pet_owner_update" on public.profile_pets
    for update to authenticated
    using ((select auth.uid())=user_id)
    with check ((select auth.uid())=user_id);
drop policy if exists "pet_owner_delete" on public.profile_pets;
create policy "pet_owner_delete" on public.profile_pets
    for delete to authenticated using ((select auth.uid())=user_id);

drop policy if exists "pet_usage_owner_select" on public.workout_pet_usage;
create policy "pet_usage_owner_select" on public.workout_pet_usage
    for select to authenticated using ((select auth.uid())=user_id);
drop policy if exists "pet_usage_owner_insert" on public.workout_pet_usage;
create policy "pet_usage_owner_insert" on public.workout_pet_usage
    for insert to authenticated with check ((select auth.uid())=user_id);
drop policy if exists "pet_usage_owner_update" on public.workout_pet_usage;
create policy "pet_usage_owner_update" on public.workout_pet_usage
    for update to authenticated
    using ((select auth.uid())=user_id)
    with check ((select auth.uid())=user_id);
drop policy if exists "pet_usage_owner_delete" on public.workout_pet_usage;
create policy "pet_usage_owner_delete" on public.workout_pet_usage
    for delete to authenticated using ((select auth.uid())=user_id);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('pet-photos','pet-photos',false,5242880,array['image/jpeg'])
on conflict(id) do nothing;
drop policy if exists "athlth_pet_photo_select" on storage.objects;
create policy "athlth_pet_photo_select" on storage.objects
    for select to authenticated using (
        bucket_id='pet-photos' and (
            (storage.foldername(name))[1]=(select auth.uid())::text
            or exists(
                select 1 from public.profile_pets p
                where p.photo_path=storage.objects.name
                  and p.is_public and p.show_on_profile
            )
        )
    );
drop policy if exists "athlth_pet_photo_insert" on storage.objects;
create policy "athlth_pet_photo_insert" on storage.objects
    for insert to authenticated with check (
        bucket_id='pet-photos' and
        (storage.foldername(name))[1]=(select auth.uid())::text
    );
drop policy if exists "athlth_pet_photo_update" on storage.objects;
create policy "athlth_pet_photo_update" on storage.objects
    for update to authenticated
    using (bucket_id='pet-photos' and (storage.foldername(name))[1]=(select auth.uid())::text)
    with check (bucket_id='pet-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "athlth_pet_photo_delete" on storage.objects;
create policy "athlth_pet_photo_delete" on storage.objects
    for delete to authenticated
    using (bucket_id='pet-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);
