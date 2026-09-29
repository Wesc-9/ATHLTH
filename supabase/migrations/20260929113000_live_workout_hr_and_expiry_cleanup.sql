-- Add optional live heart-rate context and a safe, caller-triggered cleanup path.
-- Live GPS remains one mutable latest row per participant; the UI-only trail is
-- reconstructed in memory and is never persisted.

alter table public.profile_social_settings
  add column if not exists share_live_workout_heart_rate boolean
    not null default false;

alter table public.live_workout_locations
  add column if not exists heart_rate_bpm double precision
    check (
      heart_rate_bpm is null
      or heart_rate_bpm between 20 and 260
    );

create or replace function public.cleanup_expired_live_workout_state()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  delete from public.live_workout_locations
  where expires_at <= now();

  update public.live_workout_sessions
  set status = 'completed',
      ended_at = coalesce(ended_at, now()),
      updated_at = now()
  where status in ('active','paused')
    and started_at < now() - interval '12 hours';
end;
$$;

revoke all on function public.cleanup_expired_live_workout_state()
  from public, anon;
grant execute on function public.cleanup_expired_live_workout_state()
  to authenticated;


-- Enforce presence expiry in RLS as well as in the client. A crashed app can
-- leave is_online=true behind, but authorized viewers must not be able to read
-- that stale row as current presence.
drop policy if exists social_online_presence_select_allowed
  on public.social_online_presence;
create policy social_online_presence_select_allowed
  on public.social_online_presence
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (
      is_online
      and updated_at > now() - interval '100 seconds'
      and private.can_view_online_status(user_id)
    )
  );


-- A client may only attach live heart rate after the athlete separately opted
-- in. This is enforced server-side in addition to the Swift client guard.
drop policy if exists live_workout_locations_insert_participant
  on public.live_workout_locations;
create policy live_workout_locations_insert_participant
  on public.live_workout_locations
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.live_workout_sessions l
      where l.id = session_id
        and l.status in ('active','paused')
        and (
          l.owner_id = (select auth.uid())
          or l.opponent_user_id = (select auth.uid())
        )
        and coalesce(
          (
            select settings.share_live_workout_location
            from public.profile_social_settings settings
            where settings.user_id = (select auth.uid())
          ),
          false
        )
    )
    and (
      heart_rate_bpm is null
      or coalesce(
        (
          select settings.share_live_workout_heart_rate
          from public.profile_social_settings settings
          where settings.user_id = (select auth.uid())
        ),
        false
      )
    )
  );

drop policy if exists live_workout_locations_update_participant
  on public.live_workout_locations;
create policy live_workout_locations_update_participant
  on public.live_workout_locations
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.live_workout_sessions l
      where l.id = session_id
        and l.status in ('active','paused')
        and (
          l.owner_id = (select auth.uid())
          or l.opponent_user_id = (select auth.uid())
        )
        and coalesce(
          (
            select settings.share_live_workout_location
            from public.profile_social_settings settings
            where settings.user_id = (select auth.uid())
          ),
          false
        )
    )
    and (
      heart_rate_bpm is null
      or coalesce(
        (
          select settings.share_live_workout_heart_rate
          from public.profile_social_settings settings
          where settings.user_id = (select auth.uid())
        ),
        false
      )
    )
  );
