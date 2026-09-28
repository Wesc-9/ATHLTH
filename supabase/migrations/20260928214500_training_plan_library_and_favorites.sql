-- ATHLTH Library: curated training plans + user favorites
-- Safe to deploy independently. The iOS app keeps a local fallback/cache.

create table if not exists public.training_plan_catalog (
    id uuid primary key default gen_random_uuid(),
    slug text not null unique,
    title text not null,
    summary text not null default '',
    category text not null check (category in ('running', 'strength', 'hybrid')),
    goal text not null default '',
    level text not null default 'All levels',
    duration_weeks integer not null check (duration_weeks between 1 and 52),
    sessions_per_week integer not null check (sessions_per_week between 2 and 6),
    workout_pattern text[] not null default '{}',
    tags text[] not null default '{}',
    sort_order integer not null default 100,
    is_published boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.training_plan_catalog enable row level security;

drop policy if exists "Authenticated users can read published training plans"
    on public.training_plan_catalog;
create policy "Authenticated users can read published training plans"
    on public.training_plan_catalog
    for select
    to authenticated
    using (is_published = true);

create table if not exists public.library_favorites (
    user_id uuid not null references auth.users(id) on delete cascade,
    item_type text not null check (item_type in ('plan', 'workout', 'exercise', 'route')),
    item_id text not null,
    title text not null,
    subtitle text,
    icon text,
    created_at timestamptz not null default now(),
    primary key (user_id, item_type, item_id)
);

create index if not exists library_favorites_user_created_idx
    on public.library_favorites (user_id, created_at desc);

alter table public.library_favorites enable row level security;

drop policy if exists "Users can read own library favorites"
    on public.library_favorites;
create policy "Users can read own library favorites"
    on public.library_favorites
    for select
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Users can add own library favorites"
    on public.library_favorites;
create policy "Users can add own library favorites"
    on public.library_favorites
    for insert
    to authenticated
    with check (auth.uid() = user_id);

drop policy if exists "Users can update own library favorites"
    on public.library_favorites;
create policy "Users can update own library favorites"
    on public.library_favorites
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "Users can remove own library favorites"
    on public.library_favorites;
create policy "Users can remove own library favorites"
    on public.library_favorites
    for delete
    to authenticated
    using (auth.uid() = user_id);

insert into public.training_plan_catalog (
    id, slug, title, summary, category, goal, level,
    duration_weeks, sessions_per_week, workout_pattern, tags, sort_order
)
values
    (
        'b1000000-0000-0000-0000-000000000001',
        'first-5k',
        'First 5K',
        'An approachable 8-week run plan that builds consistency before speed.',
        'running',
        'Complete a comfortable 5K',
        'Beginner',
        8,
        3,
        array['running','running','running'],
        array['5k','running','beginner'],
        10
    ),
    (
        'b1000000-0000-0000-0000-000000000002',
        '10k-builder',
        '10K Builder',
        'Build aerobic volume with running plus one supporting strength session each week.',
        'running',
        'Build toward 10K',
        'Intermediate',
        10,
        4,
        array['running','running','strength','running'],
        array['10k','running','strength'],
        20
    ),
    (
        'b1000000-0000-0000-0000-000000000003',
        'half-marathon-foundation',
        'Half Marathon Foundation',
        'A balanced 12-week structure with easy running, long-run volume and strength support.',
        'running',
        'Half marathon',
        'Intermediate',
        12,
        4,
        array['running','strength','running','running'],
        array['half-marathon','running'],
        30
    ),
    (
        'b1000000-0000-0000-0000-000000000004',
        'marathon-build',
        'Marathon Build',
        'A 16-week endurance structure for runners ready for higher weekly volume.',
        'running',
        'Marathon',
        'Advanced',
        16,
        5,
        array['running','strength','running','running','running'],
        array['marathon','running'],
        40
    ),
    (
        'b1000000-0000-0000-0000-000000000005',
        'strength-foundations',
        'Strength Foundations',
        'Three full-body sessions each week with room to customize exercises and progression.',
        'strength',
        'Build strength',
        'Beginner',
        8,
        3,
        array['strength','strength','strength'],
        array['strength','full-body'],
        50
    ),
    (
        'b1000000-0000-0000-0000-000000000006',
        'hybrid-foundation',
        'Hybrid Foundation',
        'Two running and two strength sessions each week for balanced all-round fitness.',
        'hybrid',
        'General fitness',
        'All levels',
        8,
        4,
        array['running','strength','running','strength'],
        array['hybrid','running','strength'],
        60
    )
on conflict (id) do update set
    slug = excluded.slug,
    title = excluded.title,
    summary = excluded.summary,
    category = excluded.category,
    goal = excluded.goal,
    level = excluded.level,
    duration_weeks = excluded.duration_weeks,
    sessions_per_week = excluded.sessions_per_week,
    workout_pattern = excluded.workout_pattern,
    tags = excluded.tags,
    sort_order = excluded.sort_order,
    is_published = true,
    updated_at = now();
