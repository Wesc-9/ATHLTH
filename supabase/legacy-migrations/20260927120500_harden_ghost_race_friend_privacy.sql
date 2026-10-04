create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon;
grant usage on schema private to authenticated;

create or replace function private.can_send_ghost_race(
    p_sender uuid,
    p_recipient uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select
        (select auth.uid()) is not null
        and p_sender = (select auth.uid())
        and p_sender <> p_recipient
        and exists (
            select 1
            from public.friendships f
            where
                (f.user_a = p_sender and f.user_b = p_recipient)
                or
                (f.user_b = p_sender and f.user_a = p_recipient)
        )
        and not exists (
            select 1
            from public.user_blocks b
            where
                (b.blocker_id = p_sender and b.blocked_id = p_recipient)
                or
                (b.blocker_id = p_recipient and b.blocked_id = p_sender)
        )
        and coalesce(
            (
                select p.allow_challenge_invites
                from public.profile_social_settings p
                where p.user_id = p_recipient
            ),
            'friends'
        ) <> 'nobody';
$$;

revoke all on function private.can_send_ghost_race(uuid, uuid) from public;
revoke all on function private.can_send_ghost_race(uuid, uuid) from anon;
grant execute on function private.can_send_ghost_race(uuid, uuid) to authenticated;

drop policy if exists "friends can send ghost races"
on public.ghost_race_challenges;

create policy "friends can send ghost races"
on public.ghost_race_challenges
for insert
to authenticated
with check (
    sender_id = (select auth.uid())
    and status = 'pending'
    and private.can_send_ghost_race(sender_id, recipient_id)
);
