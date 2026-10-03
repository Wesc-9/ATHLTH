-- ATHLTH 1.5.9: make intentional internal-only RLS explicit.
-- Service-role backend code continues to bypass RLS; anonymous/authenticated
-- clients remain denied exactly as before.

drop policy if exists community_group_member_workouts_internal_only
on public.community_group_member_workouts;

create policy community_group_member_workouts_internal_only
on public.community_group_member_workouts
for all
to anon, authenticated
using (false)
with check (false);

drop policy if exists public_trail_fetch_cells_internal_only
on public.public_trail_fetch_cells;

create policy public_trail_fetch_cells_internal_only
on public.public_trail_fetch_cells
for all
to anon, authenticated
using (false)
with check (false);
