-- Arena Club series: server-verified Club membership, invitation privacy
-- and manager-only publishing. Preserve the separate Club Weekly Challenge.
alter table public.arena_series
 add column if not exists club_id uuid references public.community_groups(id) on delete set null;
alter table public.arena_series
 drop constraint if exists arena_series_scope_check;
alter table public.arena_series
 add constraint arena_series_scope_check check (scope in ('duel','friends','club'));
alter table public.arena_series
 add constraint arena_club_scope_matches_group check (
   (scope='club' and club_id is not null) or
   (scope<>'club' and club_id is null)
 );
create index if not exists arena_series_club_idx
 on public.arena_series(club_id,created_at desc) where club_id is not null;

create or replace function public.arena_publish_club_series(
 p_club uuid, p_title text, p_scoring text, p_duration_days integer,
 p_invitees uuid[], p_rounds jsonb
) returns uuid language plpgsql security invoker
set search_path=pg_catalog,public,private
as $$
declare
 v_actor uuid := (select auth.uid());
 v_series uuid;
 v_user uuid;
 v_round jsonb;
 v_position integer := 0;
begin
 if v_actor is null then raise exception 'Sign in required'; end if;
 if p_club is null or not private.can_manage_community_group(p_club) then
   raise exception 'Only Club admins may publish Club Arena competitions';
 end if;
 if p_title is null or length(btrim(p_title)) not between 1 and 80
   or p_scoring not in ('winner','podium')
   or p_duration_days not between 1 and 90 then
   raise exception 'Invalid Club competition settings';
 end if;
 if p_invitees is null or cardinality(p_invitees) not between 1 and 20
   or v_actor=any(p_invitees)
   or (select count(distinct x) from unnest(p_invitees) x) <> cardinality(p_invitees) then
   raise exception 'Select 1 to 20 unique Club athletes other than yourself';
 end if;
 if jsonb_typeof(p_rounds) is distinct from 'array'
   or jsonb_array_length(p_rounds) not between 1 and 16 then
   raise exception 'Select 1 to 16 rounds';
 end if;
 foreach v_user in array p_invitees loop
   if not exists (
     select 1 from public.community_group_members gm
     where gm.group_id=p_club and gm.user_id=v_user
   ) then raise exception 'Invitee is not a Club member'; end if;
   if not private.arena_can_invite(v_user) then
     raise exception 'An invitee does not allow Arena invitations';
   end if;
 end loop;
 insert into public.arena_series(owner_id,title,scope,scoring,duration_days,club_id)
 values(v_actor,btrim(p_title),'club',p_scoring,p_duration_days,p_club)
 returning id into v_series;
 foreach v_user in array p_invitees loop
   insert into public.arena_series_members(series_id,user_id,response)
   values(v_series,v_user,'invited');
 end loop;
 for v_round in select value from jsonb_array_elements(p_rounds) loop
   insert into public.arena_round_proposals(
    series_id,proposed_by,template,title,rules,position
   ) values(
    v_series,v_actor,v_round->>'template',v_round->>'title',
    v_round->>'rules',v_position
   );
   v_position := v_position+1;
 end loop;
 return v_series;
end;
$$;
revoke all on function public.arena_publish_club_series(
 uuid,text,text,integer,uuid[],jsonb
) from public,anon;
grant execute on function public.arena_publish_club_series(
 uuid,text,text,integer,uuid[],jsonb
) to authenticated;
