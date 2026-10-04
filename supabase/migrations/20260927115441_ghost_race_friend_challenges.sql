create table if not exists public.ghost_race_challenges (
    id uuid primary key default gen_random_uuid(),
    sender_id uuid not null references public.profiles(id) on delete cascade,
    recipient_id uuid not null references public.profiles(id) on delete cascade,
    title text not null check (char_length(title) between 1 and 160),
    reference_duration_seconds double precision not null check (reference_duration_seconds > 0),
    distance_meters double precision not null check (distance_meters > 0),
    route_points jsonb not null default '[]'::jsonb
        check (
            jsonb_typeof(route_points) = 'array'
            and jsonb_array_length(route_points) between 2 and 400
        ),
    privacy_trimmed boolean not null default true,
    status text not null default 'pending'
        check (status in ('pending', 'accepted', 'declined', 'cancelled')),
    created_at timestamptz not null default now(),
    responded_at timestamptz,
    expires_at timestamptz not null default (now() + interval '30 days'),
    check (sender_id <> recipient_id)
);

create index if not exists ghost_race_challenges_recipient_status_idx
    on public.ghost_race_challenges(recipient_id, status, created_at desc);

create index if not exists ghost_race_challenges_sender_status_idx
    on public.ghost_race_challenges(sender_id, status, created_at desc);

alter table public.ghost_race_challenges enable row level security;

revoke all on public.ghost_race_challenges from anon;
revoke all on public.ghost_race_challenges from authenticated;
grant select, insert on public.ghost_race_challenges to authenticated;
grant update(status, responded_at) on public.ghost_race_challenges to authenticated;

drop policy if exists "ghost races visible to participants" on public.ghost_race_challenges;
create policy "ghost races visible to participants"
on public.ghost_race_challenges
for select
to authenticated
using (
    (select auth.uid()) is not null
    and (
        sender_id = (select auth.uid())
        or recipient_id = (select auth.uid())
    )
);

drop policy if exists "friends can send ghost races" on public.ghost_race_challenges;
create policy "friends can send ghost races"
on public.ghost_race_challenges
for insert
to authenticated
with check (
    (select auth.uid()) is not null
    and sender_id = (select auth.uid())
    and recipient_id <> (select auth.uid())
    and status = 'pending'
    and exists (
        select 1
        from public.friendships f
        where
            (f.user_a = sender_id and f.user_b = recipient_id)
            or
            (f.user_b = sender_id and f.user_a = recipient_id)
    )
    and not exists (
        select 1
        from public.user_blocks b
        where
            (b.blocker_id = sender_id and b.blocked_id = recipient_id)
            or
            (b.blocker_id = recipient_id and b.blocked_id = sender_id)
    )
    and coalesce(
        (
            select p.allow_challenge_invites
            from public.profile_social_settings p
            where p.user_id = recipient_id
        ),
        'friends'
    ) <> 'nobody'
);

drop policy if exists "participants can respond to ghost races" on public.ghost_race_challenges;
create policy "participants can respond to ghost races"
on public.ghost_race_challenges
for update
to authenticated
using (
    sender_id = (select auth.uid())
    or recipient_id = (select auth.uid())
)
with check (
    (
        recipient_id = (select auth.uid())
        and status in ('accepted', 'declined')
    )
    or
    (
        sender_id = (select auth.uid())
        and status = 'cancelled'
    )
);
