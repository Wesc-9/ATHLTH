-- Allow Club admins to correct season links only before a competition starts.
-- No result, point, or workout evidence is changed by this function.
create or replace function public.arena_detach_club_season_series(
    p_season uuid,
    p_series uuid
) returns void
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
    v_season public.arena_club_seasons%rowtype;
    v_series public.arena_series%rowtype;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    select * into v_season
    from public.arena_club_seasons
    where id = p_season
    for update;

    if not found or not private.can_manage_community_group(v_season.club_id) then
        raise exception 'Club administrator access required';
    end if;
    if now()::date > v_season.ends_on then
        raise exception 'Ended season links cannot be changed';
    end if;

    select * into v_series
    from public.arena_series
    where id = p_series
    for update;

    if not found
        or v_series.scope <> 'club'
        or v_series.club_id is distinct from v_season.club_id
        or v_series.status <> 'draft' then
        raise exception 'Only unstarted competitions in this Club can be unlinked';
    end if;

    delete from public.arena_club_season_series
    where season_id = p_season
      and series_id = p_series;
end;
$$;

revoke all on function public.arena_detach_club_season_series(uuid,uuid)
    from public,anon;
grant execute on function public.arena_detach_club_season_series(uuid,uuid)
    to authenticated;
comment on function public.arena_detach_club_season_series(uuid,uuid)
    is 'Club-admin only; unlinks an unstarted competition without changing results or historical points.';
