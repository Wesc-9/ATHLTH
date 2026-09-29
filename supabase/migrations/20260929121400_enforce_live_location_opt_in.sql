-- Require the athlete's live-location toggle for every remote viewer,
-- including accepted Ghost Race opponents.

create or replace function private.can_view_live_workout(p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select
        (select auth.uid()) is not null
        and (
            p_owner = (select auth.uid())
            or (
                coalesce(
                    (
                        select s.share_live_workout_location
                        from public.profile_social_settings s
                        where s.user_id = p_owner
                    ),
                    false
                )
                and not exists (
                    select 1
                    from public.user_blocks b
                    where
                        (b.blocker_id = p_owner and b.blocked_id = (select auth.uid()))
                        or
                        (b.blocker_id = (select auth.uid()) and b.blocked_id = p_owner)
                )
                and (
                    (
                        exists (
                            select 1
                            from public.profile_follows me
                            where me.follower_id = (select auth.uid())
                              and me.following_id = p_owner
                        )
                        and exists (
                            select 1
                            from public.profile_follows them
                            where them.follower_id = p_owner
                              and them.following_id = (select auth.uid())
                        )
                    )
                    or exists (
                        select 1
                        from public.ghost_race_challenges g
                        where g.status = 'accepted'
                          and g.expires_at > now()
                          and (
                              (g.sender_id = p_owner and g.recipient_id = (select auth.uid()))
                              or
                              (g.recipient_id = p_owner and g.sender_id = (select auth.uid()))
                          )
                    )
                )
            )
        );
$$;
