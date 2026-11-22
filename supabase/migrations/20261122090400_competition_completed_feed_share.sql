create or replace function public.athlth_tournament_publish_feed(p_tournament uuid)
returns uuid language plpgsql security definer set search_path='' as $fn$
declare t public.athlth_tournaments%rowtype;
 post_id uuid; people text; event_key text;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments
 where id=p_tournament for update;
 if not found or t.owner_id<>auth.uid() then
    raise exception 'Only the competition organizer may publish'; end if;
 if not t.competition_settings_applied or t.status<>'completed'
    or t.completed_at is null or not t.allow_feed_post then
    raise exception 'Sharing not allowed until competition is completed'; end if;
 if exists(select 1 from public.athlth_tournament_entries e
           where e.tournament_id=t.id and e.response='accepted'
           and e.removed_at is null
           and (e.agreed_rule_version is distinct from t.rule_version
                or e.agreed_rules_at is null)) then
    raise exception 'All named participants must have agreed to sharing'; end if;
 event_key:='tournament_result:'||t.id::text;
 select a.id into post_id from public.social_activities a
 where a.actor_id=t.owner_id and a.event_key=event_key;
 if post_id is not null then return post_id; end if;
 select string_agg(left(coalesce(nullif(btrim(p.username),''),'Utøver'),32),
                   ', ' order by e.seed) into people
 from public.athlth_tournament_entries e
 join public.profiles p on p.id=e.user_id
 where e.tournament_id=t.id and e.response='accepted'
   and e.removed_at is null and e.user_id<>t.owner_id
   and e.agreed_rule_version=t.rule_version and e.agreed_rules_at is not null;
 insert into public.social_activities(actor_id,kind,title,subtitle,metadata,visibility,event_key)
 values(t.owner_id,'challenge',left('Konkurranse fullført · '||t.title,160),
        left('Sammen med '||coalesce(people,'deltakerne'),300),
        jsonb_build_object('tournament_id',t.id::text,'tournament_format',t.format,
                           'with_names',left(coalesce(people,''),260),
                           'source','athlth_tournament'),
        'friends',event_key)
 returning id into post_id;
 update public.athlth_tournaments
 set feed_published_at=clock_timestamp() where id=t.id;
 return post_id;
end;$fn$;
revoke all on function public.athlth_tournament_publish_feed(uuid) from public,anon;
grant execute on function public.athlth_tournament_publish_feed(uuid) to authenticated;