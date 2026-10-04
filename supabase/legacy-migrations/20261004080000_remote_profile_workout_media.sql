-- ATHLTH 1.6.0: let profile visitors see workout photos/highlights
-- only when the owner shares Recent activity with that viewer.

drop policy if exists "workout media owner read"
on public.workout_media;

drop policy if exists "workout media visible profile read"
on public.workout_media;

create policy "workout media visible profile read"
on public.workout_media
for select
to authenticated
using (
  user_id = (select auth.uid())
  or private.can_view_social_section(
    user_id,
    'activity'
  )
);
