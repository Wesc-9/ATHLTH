-- Give winners a permanent ATHLTH trophy when a verified tournament
-- finishes. The server, never the client, decides the champion.
-- Awards retain a unique tournament stage key; reruns cannot duplicate them.
create or replace function private.athlth_tournament_grant_completed_awards()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 v_winner uuid;
 v_runner_up uuid;
 v_third uuid;
 v_final public.athlth_tournament_matches%rowtype;
 v_count integer;
begin
 if new.status<>'completed' or old.status='completed' then
   return new;
 end if;
 if new.format='league' then
   if not exists(
     select 1 from public.athlth_tournament_matches
     where tournament_id=new.id and phase='league' and status='confirmed'
   ) then return new; end if;
   select s.user_id into v_winner
     from public.athlth_tournament_standings(new.id,null) s
     order by s.points desc,(s.scored-s.conceded) desc,
              s.scored desc,s.wins desc,s.rank,s.user_id
     limit 1;
   select s.user_id into v_runner_up
     from public.athlth_tournament_standings(new.id,null) s
     order by s.points desc,(s.scored-s.conceded) desc,
              s.scored desc,s.wins desc,s.rank,s.user_id
     offset 1 limit 1;
   select s.user_id into v_third
     from public.athlth_tournament_standings(new.id,null) s
     order by s.points desc,(s.scored-s.conceded) desc,
              s.scored desc,s.wins desc,s.rank,s.user_id
     offset 2 limit 1;
 else
   -- In an elimination bracket only the last confirmed final may
   -- determine a champion. Never award a tied or disputed fixture.
   select count(*) into v_count from public.athlth_tournament_matches m
    where m.tournament_id=new.id and m.phase in ('cup','playoff')
      and m.round_number=(
        select max(round_number) from public.athlth_tournament_matches
        where tournament_id=new.id and phase in ('cup','playoff')
      );
   if v_count<>1 then return new; end if;
   select * into v_final from public.athlth_tournament_matches
    where tournament_id=new.id and phase in ('cup','playoff')
    order by round_number desc limit 1;
   if v_final.status<>'confirmed' or v_final.home_id is null or
      v_final.away_id is null or v_final.home_score is null or
      v_final.away_score is null or v_final.home_score=v_final.away_score then
      return new;
   end if;
   v_winner:=case when v_final.home_score>v_final.away_score
                  then v_final.home_id else v_final.away_id end;
   v_runner_up:=case when v_final.home_score<v_final.away_score
                  then v_final.home_id else v_final.away_id end;
 end if;

 if v_winner is null then return new; end if;
 insert into public.athlth_award_unlocks(
   user_id,stage_key,award_id,award_class,
   stage_title,title,rarity,category,verification_source,
   system_image,unlocked_at,evidence,username_at_unlock
 ) select v_winner,
   'arena.tournament.'||new.id::text||'.champion',
   'tournament.'||new.id::text||'.champion','trophy',
   new.title,'Mester · '||new.title,'epic','challenges',
   'challenge','trophy.fill',coalesce(new.completed_at,now()),
   jsonb_build_object('tournament_id',new.id,'format',new.format,
                      'placement',1,'server_verified',true),
   p.username from public.profiles p where p.id=v_winner
 on conflict(user_id,stage_key) do nothing;

 if v_runner_up is not null then
   insert into public.athlth_award_unlocks(
     user_id,stage_key,award_id,award_class,
     stage_title,title,rarity,category,verification_source,
     system_image,unlocked_at,evidence,username_at_unlock
   ) select v_runner_up,
     'arena.tournament.'||new.id::text||'.runnerup',
     'tournament.'||new.id::text||'.runnerup','achievement',
     new.title,'Sølv · '||new.title,'rare','challenges',
     'challenge','medal.fill',coalesce(new.completed_at,now()),
     jsonb_build_object('tournament_id',new.id,'format',new.format,
                        'placement',2,'server_verified',true),
     p.username from public.profiles p where p.id=v_runner_up
   on conflict(user_id,stage_key) do nothing;
 end if;

 if v_third is not null then
   insert into public.athlth_award_unlocks(
     user_id,stage_key,award_id,award_class,
     stage_title,title,rarity,category,verification_source,
     system_image,unlocked_at,evidence,username_at_unlock
   ) select v_third,
     'arena.tournament.'||new.id::text||'.third',
     'tournament.'||new.id::text||'.third','achievement',
     new.title,'Bronse · '||new.title,'core','challenges',
     'challenge','medal.fill',coalesce(new.completed_at,now()),
     jsonb_build_object('tournament_id',new.id,'format',new.format,
                        'placement',3,'server_verified',true),
     p.username from public.profiles p where p.id=v_third
   on conflict(user_id,stage_key) do nothing;
 end if;
 return new;
end;
$$;

drop trigger if exists athlth_tournament_completed_awards
 on public.athlth_tournaments;
create trigger athlth_tournament_completed_awards
after update of status on public.athlth_tournaments
for each row
when (new.status='completed' and old.status is distinct from new.status)
execute function private.athlth_tournament_grant_completed_awards();

revoke all on function private.athlth_tournament_grant_completed_awards()
 from public,anon,authenticated;
