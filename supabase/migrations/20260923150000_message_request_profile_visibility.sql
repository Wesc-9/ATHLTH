create or replace function private.can_view_profile_card(owner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select
    (select auth.uid()) = owner_id
    or exists (
      select 1
      from public.user_blocks b
      where b.blocker_id = (select auth.uid())
        and b.blocked_id = owner_id
    )
    or (
      not private.is_blocked(owner_id)
      and (
        coalesce((
          select s.discoverable
          from public.profile_social_settings s
          where s.user_id = owner_id
        ), false)
        or private.are_friends(owner_id)
        or exists (
          select 1
          from public.friend_requests fr
          where (
            (fr.sender_id = (select auth.uid()) and fr.recipient_id = owner_id)
            or (fr.recipient_id = (select auth.uid()) and fr.sender_id = owner_id)
          )
          and fr.status = 'pending'
        )
        or exists (
          select 1
          from public.direct_conversations dc
          where dc.request_status in ('pending', 'accepted')
            and (
              (dc.user_a = (select auth.uid()) and dc.user_b = owner_id)
              or
              (dc.user_b = (select auth.uid()) and dc.user_a = owner_id)
            )
        )
        or exists (
          select 1
          from public.social_challenge_participants me
          join public.social_challenge_participants them
            on them.challenge_id = me.challenge_id
          where me.user_id = (select auth.uid())
            and them.user_id = owner_id
            and me.state in ('creator','invited','accepted')
            and them.state in ('creator','invited','accepted')
        )
      )
    );
$$;
