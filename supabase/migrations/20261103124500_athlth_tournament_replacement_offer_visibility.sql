-- The prospective replacement must be able to open the specific
-- tournament invitation without gaining access to its private lobby chat.
create or replace function private.athlth_tournament_can_view(
 p_tournament uuid
) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
   select 1 from public.athlth_tournaments t
   where t.id=p_tournament and (
      t.owner_id=auth.uid()
      or exists(select 1 from public.athlth_tournament_entries e
                where e.tournament_id=t.id and e.user_id=auth.uid())
      or exists(select 1 from public.athlth_tournament_player_change r
                where r.tournament_id=t.id and r.new_player_id=auth.uid()
                  and r.status='pending')
      or (t.club_id is not null and exists(
           select 1 from public.community_group_members m
            where m.group_id=t.club_id and m.user_id=auth.uid()))
   )
 );
$$;
revoke all on function private.athlth_tournament_can_view(uuid) from public,anon;
grant execute on function private.athlth_tournament_can_view(uuid) to authenticated;
