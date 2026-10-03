-- ATHLTH 1.5.9 release hardening.
-- Reconcile production defaults, add persistent public-event covers,
-- allow safe self-join for discoverable public challenges, and remove
-- known RLS performance warnings without changing authorization semantics.

-- Profile sections should be visible by default for new accounts.
-- Existing rows and explicit user choices are intentionally untouched.
alter table public.profile_social_settings
  alter column training_focus_visibility set default 'public',
  alter column performance_stats_visibility set default 'public',
  alter column trophy_cabinet_visibility set default 'public',
  alter column recent_activity_visibility set default 'public',
  alter column goals_visibility set default 'public',
  alter column gear_visibility set default 'public',
  alter column running_prs_visibility set default 'public',
  alter column strength_prs_visibility set default 'public',
  alter column share_performance_stats set default true,
  alter column share_trophy_cabinet set default true,
  alter column share_goals set default true,
  alter column share_gear set default true,
  alter column share_recent_activity set default true,
  alter column share_running_prs set default true,
  alter column share_strength_prs set default true,
  alter column share_workout_totals set default true;

-- Public Community events now use the same persistent cover model as challenges.
alter table public.community_events
  add column if not exists cover_artwork_name text,
  add column if not exists cover_image_url text,
  alter column meeting_name set default '';

-- Public challenges may be created without direct invitees. Signed-in users
-- can explicitly join a discoverable challenge without opening participant
-- INSERT permissions broadly.
create or replace function public.join_public_social_challenge(
  p_challenge_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  challenge_creator uuid;
  existing_participant uuid;
  participant_id uuid;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  select c.creator_id
    into challenge_creator
  from public.social_challenges c
  where c.id = p_challenge_id
    and c.visibility = 'public'
    and c.status in ('invited', 'upcoming', 'active')
    and (c.ends_at is null or c.ends_at > now());

  if challenge_creator is null then
    raise exception 'Public challenge is not available';
  end if;

  if challenge_creator = actor then
    select p.id
      into existing_participant
    from public.social_challenge_participants p
    where p.challenge_id = p_challenge_id
      and p.user_id = actor
    limit 1;

    if existing_participant is null then
      raise exception 'Challenge creator participant is missing';
    end if;

    return existing_participant;
  end if;

  if public.is_blocked_pair(actor, challenge_creator) then
    raise exception 'Challenge is not available';
  end if;

  select p.id
    into existing_participant
  from public.social_challenge_participants p
  where p.challenge_id = p_challenge_id
    and p.user_id = actor
  limit 1;

  if existing_participant is not null then
    update public.social_challenge_participants
    set
      state = 'accepted',
      responded_at = now()
    where id = existing_participant
      and state in ('invited', 'declined');

    return existing_participant;
  end if;

  participant_id := gen_random_uuid();

  insert into public.social_challenge_participants (
    id,
    challenge_id,
    user_id,
    state,
    invited_by,
    invited_at,
    responded_at
  )
  values (
    participant_id,
    p_challenge_id,
    actor,
    'accepted',
    challenge_creator,
    now(),
    now()
  );

  return participant_id;
end;
$$;

revoke all on function public.join_public_social_challenge(uuid)
from public, anon;

grant execute on function public.join_public_social_challenge(uuid)
to authenticated;

-- Avoid re-evaluating auth.uid() for every row in these high-frequency RLS policies.
drop policy if exists "Users can read their workout hero assets"
on public.workout_hero_assets;
create policy "Users can read their workout hero assets"
on public.workout_hero_assets for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can add own library favorites"
on public.library_favorites;
create policy "Users can add own library favorites"
on public.library_favorites for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can read own library favorites"
on public.library_favorites;
create policy "Users can read own library favorites"
on public.library_favorites for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can remove own library favorites"
on public.library_favorites;
create policy "Users can remove own library favorites"
on public.library_favorites for delete
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can update own library favorites"
on public.library_favorites;
create policy "Users can update own library favorites"
on public.library_favorites for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- The previous two permissive DELETE policies expressed the same authorization
-- as an OR. Combine them so Postgres evaluates one policy per delete.
drop policy if exists group_members_leave_self
on public.community_group_members;
drop policy if exists group_members_remove_managers
on public.community_group_members;

create policy group_members_delete_allowed
on public.community_group_members for delete
to authenticated
using (
  role <> 'owner'
  and (
    user_id = (select auth.uid())
    or private.can_manage_community_group(group_id)
  )
);
