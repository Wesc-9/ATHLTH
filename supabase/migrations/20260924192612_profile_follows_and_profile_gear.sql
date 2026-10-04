-- ATHLTH 1.3.8: profile follows and user-managed profile gear

create table if not exists public.profile_follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint profile_follows_no_self check (follower_id <> following_id)
);

create index if not exists profile_follows_following_idx
  on public.profile_follows (following_id, created_at desc);

create index if not exists profile_follows_follower_idx
  on public.profile_follows (follower_id, created_at desc);

alter table public.profile_follows enable row level security;

create policy "authenticated users can read follows"
  on public.profile_follows
  for select
  to authenticated
  using (true);

create policy "users can follow from their own account"
  on public.profile_follows
  for insert
  to authenticated
  with check (auth.uid() = follower_id and follower_id <> following_id);

create policy "users can unfollow from their own account"
  on public.profile_follows
  for delete
  to authenticated
  using (auth.uid() = follower_id);

grant select, insert, delete on public.profile_follows to authenticated;

create table if not exists public.profile_gear (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  category text not null check (category in ('watch', 'shoes', 'headphones', 'other')),
  name text not null check (char_length(trim(name)) between 1 and 80),
  image_url text,
  is_featured boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists profile_gear_user_category_idx
  on public.profile_gear (user_id, category, created_at desc);

create unique index if not exists profile_gear_one_featured_per_category
  on public.profile_gear (user_id, category)
  where is_featured;

alter table public.profile_gear enable row level security;

create policy "authenticated users can view profile gear"
  on public.profile_gear
  for select
  to authenticated
  using (true);

create policy "users can add their own profile gear"
  on public.profile_gear
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "users can update their own profile gear"
  on public.profile_gear
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "users can delete their own profile gear"
  on public.profile_gear
  for delete
  to authenticated
  using (auth.uid() = user_id);

grant select, insert, update, delete on public.profile_gear to authenticated;

insert into storage.buckets (id, name, public)
values ('profile-gear', 'profile-gear', true)
on conflict (id) do update set public = excluded.public;

create policy "profile gear images are publicly readable"
  on storage.objects
  for select
  to public
  using (bucket_id = 'profile-gear');

create policy "users can upload own profile gear images"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'profile-gear'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users can update own profile gear images"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'profile-gear'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'profile-gear'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users can delete own profile gear images"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'profile-gear'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
