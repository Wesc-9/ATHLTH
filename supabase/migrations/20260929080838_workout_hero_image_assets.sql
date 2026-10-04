create table if not exists public.workout_hero_assets (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    workout_id uuid not null,
    status text not null default 'generating'
        check (status in ('generating', 'ready', 'failed')),
    storage_path text,
    model text,
    prompt_version text,
    recipe jsonb,
    attempts integer not null default 0,
    last_error text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id, workout_id)
);

create index if not exists workout_hero_assets_user_updated_idx
    on public.workout_hero_assets(user_id, updated_at desc);

alter table public.workout_hero_assets enable row level security;

drop policy if exists "Users can read their workout hero assets"
    on public.workout_hero_assets;

create policy "Users can read their workout hero assets"
    on public.workout_hero_assets
    for select
    to authenticated
    using (auth.uid() = user_id);

insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
values (
    'workout-hero-images',
    'workout-hero-images',
    false,
    8388608,
    array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
