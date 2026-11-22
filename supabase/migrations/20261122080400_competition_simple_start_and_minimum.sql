CREATE OR REPLACE FUNCTION public.athlth_tournament_create_simple(p_title text, p_format text, p_activity text, p_invitees uuid[], p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_owner uuid := auth.uid();
    v_id uuid;
    v_template uuid;
    v_title text;
begin
    if v_owner is null then raise exception 'Sign in required'; end if;
    if p_format not in ('league','cup') or
       p_activity not in ('running','walking','strength') or
       (coalesce(array_length(p_invitees,1),0)<(case when p_format='cup' then 3 else 1 end)
        or coalesce(array_length(p_invitees,1),0)>20) or
       length(btrim(coalesce(p_title,''))) not between 3 and 80 then
        raise exception 'Invalid Basic competition settings';
    end if;
    if p_starts_at is not null and
       (p_starts_at<clock_timestamp()-interval '1 minute' or
        p_starts_at>clock_timestamp()+interval '366 days') then
       raise exception 'Choose a future start date';
    end if;
    v_title:=case p_activity
      when 'running' then 'Løp 5 km'
      when 'walking' then 'Gå 5 km'
      when 'strength' then 'Knebøy – flest repetisjoner'
    end;
    select id into v_template
    from public.athlth_tournament_activity_templates
    where title=v_title and activity_type=p_activity and is_active
    order by id limit 1;
    if v_template is null then
       raise exception 'Default activity is currently unavailable';
    end if;

    v_id:=public.athlth_tournament_create_competition(
       p_title,p_format,null::uuid,null::uuid,4,2,
       p_invitees,ARRAY[]::text[],'owner',1,null::timestamptz,
       null::timestamptz,false,ARRAY[p_activity],'owner',
       7,48,'all',ARRAY[]::integer[],'opponent',
       false,true,3,1,
       jsonb_build_object(
          'startsAt',p_starts_at,'startMode',case when p_starts_at is null then 'when_ready' else 'scheduled' end,
          'unlock','interval',
          'every',7,'unit','day','invitationPermission','admin',
          'joinApproval','admin','allowed','','prohibited','',
          'firstPrize','','secondPrize','','thirdPrize','',
          'loserConsequence',''
       )
    );
    insert into public.athlth_tournament_exercise_candidates(
        tournament_id,activity_template_id,suggested_by,selected_position
    ) values(v_id,v_template,v_owner,1);
    update public.athlth_tournaments
       set simple_mode=true,exercise_selection_finalized_at=clock_timestamp()
       where id=v_id;
    -- Creator explicitly chose Basic defaults when pressing Publish.
    update public.athlth_tournament_entries
       set agreed_rule_version=1,agreed_rules_at=clock_timestamp(),
           is_ready=true,ready_at=clock_timestamp()
       where tournament_id=v_id and user_id=v_owner and response='accepted';
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event,info
    ) values(v_id,v_owner,'simple_setup_completed',
       jsonb_build_object('activity',p_activity,'exercise',v_template));
    return v_id;
end;
$function$
