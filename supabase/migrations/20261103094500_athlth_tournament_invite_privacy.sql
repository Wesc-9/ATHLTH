-- Respect recipient privacy before sending personal and club invitations.
-- Existing tournaments and accepted invitations are not modified.
create or replace function public.athlth_tournament_create(
    p_title text, p_format text, p_club uuid, p_season uuid,
    p_group_size integer, p_qualifiers integer,
    p_invitees uuid[], p_warmup_titles text[]
) returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
    v_owner uuid := auth.uid();
    v_id uuid;
    v_invitee uuid;
    v_index integer := 1;
    v_title text;
    v_club_allowed boolean;
    v_warmup text;
begin
    if v_owner is null then raise exception 'Sign in required'; end if;
    if p_title is null or length(btrim(p_title)) not between 3 and 80 or
       p_format not in ('league','groups','cup') or
       p_group_size not between 2 and 16 or
       p_qualifiers not between 1 and p_group_size then
        raise exception 'Invalid tournament settings';
    end if;
    if coalesce(array_length(p_invitees,1),0) < 1 or
       coalesce(array_length(p_invitees,1),0) > 127 or
       coalesce(array_length(p_warmup_titles,1),0) > 12 then
        raise exception 'Invalid participant or warmup count';
    end if;
    if v_owner=any(p_invitees) or
       exists(select 1 from unnest(p_invitees) x
              where x is null) or
       (select count(distinct x) from unnest(p_invitees) x) <>
       coalesce(array_length(p_invitees,1),0) or
       (select count(*) from public.profiles p
        where p.id=any(p_invitees)) <> coalesce(array_length(p_invitees,1),0) then
        raise exception 'Invalid or duplicate invited users';
    end if;
    if p_club is null and p_season is not null then
        raise exception 'Personal tournaments cannot join club seasons';
    end if;
    if p_club is not null then
        select exists(
            select 1 from public.community_group_members m
            where m.group_id=p_club and m.user_id=v_owner
              and m.role='owner'
        ) into v_club_allowed;
        if not v_club_allowed then
            raise exception 'Only club owners may create club tournaments';
        end if;
        if p_season is not null and not exists(
            select 1 from public.arena_club_seasons s
            where s.id=p_season and s.club_id=p_club
                and current_date <= s.ends_on
        ) then
            raise exception 'Season does not belong to this club or has ended';
        end if;
    end if;
    -- An external invitation must respect the recipient's privacy choices.
    -- Mutual friends and members of the same club may invite users who chose
    -- "friends"; complete strangers require the "everyone" setting.
    -- A block in either direction and "nobody" always prohibit invitations.
    if exists (
        select 1 from unnest(p_invitees) as target(user_id)
        left join public.profile_social_settings settings
          on settings.user_id=target.user_id
        where
          exists (
            select 1 from public.user_blocks b
             where (b.blocker_id=v_owner and b.blocked_id=target.user_id)
                or (b.blocker_id=target.user_id and b.blocked_id=v_owner)
          )
          or coalesce(settings.allow_challenge_invites,'friends')='nobody'
          or (
            not exists (
                select 1 from public.profile_follows outgoing
                join public.profile_follows incoming
                  on incoming.follower_id=target.user_id
                 and incoming.following_id=v_owner
                where outgoing.follower_id=v_owner
                  and outgoing.following_id=target.user_id
            )
            and not (
                p_club is not null and exists (
                    select 1 from public.community_group_members m
                    where m.group_id=p_club and m.user_id=target.user_id
                )
            )
            and (
                coalesce(settings.allow_challenge_invites,'friends')<>'everyone'
                or coalesce(settings.discoverable,false)=false
            )
          )
    ) then
        raise exception 'One or more athletes cannot receive this invitation';
    end if;
    if (
        select count(*) from public.athlth_tournaments t
        where t.owner_id=v_owner
          and t.created_at>now()-interval '24 hours'
    )>=15 then
        raise exception 'Daily tournament invitation limit reached';
    end if;
    insert into public.athlth_tournaments(
        owner_id, club_id, season_id, title, format,
        group_size, qualifiers_per_group
    ) values (
        v_owner,p_club,p_season,btrim(p_title),p_format,
        p_group_size,p_qualifiers
    ) returning id into v_id;
    insert into public.athlth_tournament_entries(
        tournament_id,user_id,seed,response,responded_at
    ) values(v_id,v_owner,1,'accepted',now());
    foreach v_invitee in array p_invitees loop
        v_index:=v_index+1;
        insert into public.athlth_tournament_entries(
            tournament_id,user_id,seed,response
        ) values(v_id,v_invitee,v_index,'invited');
    end loop;
    v_index:=0;
    foreach v_warmup in array coalesce(p_warmup_titles,array[]::text[]) loop
        if v_warmup is null or length(btrim(v_warmup)) not between 1 and 60 then
            raise exception 'Invalid practice round title';
        end if;
        v_index:=v_index+1;
        insert into public.athlth_tournament_practice(
            tournament_id,ordinal,title
        ) values(v_id,v_index,btrim(v_warmup));
    end loop;
    insert into public.athlth_tournament_audit(tournament_id,actor_id,event)
    values(v_id,v_owner,'created');
    return v_id;
end;
$$;

revoke all on function public.athlth_tournament_create(
 text,text,uuid,uuid,integer,integer,uuid[],text[]) from public,anon;
grant execute on function public.athlth_tournament_create(
 text,text,uuid,uuid,integer,integer,uuid[],text[]) to authenticated;
