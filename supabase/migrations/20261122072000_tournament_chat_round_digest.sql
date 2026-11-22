-- Concise competition updates delivered by pg_cron, not by every score change.
-- The private log gives exactly-once publication, including retried jobs.
create or replace function private.athlth_competition_publish_chat_digest()
returns integer language plpgsql security definer
set search_path='' as $fn$
declare
    v record;
    v_reminder record;
    v_message text;
    v_count integer:=0;
    v_done boolean;
begin
    -- One meaningful "started" notification, including to the organizer.
    for v in
        select id,title from public.athlth_tournaments
        where competition_settings_applied and status='active'
            and started_at is not null
    loop
        if private.athlth_competition_post_system(
            v.id,'start',
            'Konkurransen er i gang! Se øvelser og frister i konkurranseoversikten.',
            true
        ) then v_count:=v_count+1; end if;
    end loop;

    -- Once per tournament round + exercise, irrespective of how many
    -- pairings are in the same league/group/cup. Do not alert for slots
    -- that have not yet opened, or were already closed before polling.
    for v in
        select distinct s.tournament_id,m.phase,m.round_number,s.position
        from public.athlth_tournament_match_exercises s
        join public.athlth_tournament_matches m on m.id=s.match_id
        join public.athlth_tournaments t on t.id=s.tournament_id
        where t.competition_settings_applied and t.status='active'
          and m.phase<>'warmup' and s.state='pending'
          and s.scheduled_at<=clock_timestamp()
          and s.deadline_at>clock_timestamp()
    loop
        v_message:='Runde '||v.round_number||' · øvelse '||
            v.position||' er klar. Se din øvelse og gjennomføringsfrist.';
        if private.athlth_competition_post_system(
            v.tournament_id,
            'exercise:'||v.phase||':'||v.round_number||':'||v.position,
            v_message, true
        ) then v_count:=v_count+1; end if;
    end loop;

    -- Summarize completed rounds only when ALL matches in a round are
    -- confirmed. This is a single chat update, WITHOUT a second push
    -- after each individual match or when a next-exercise push follows.
    for v in
        select m.tournament_id,m.phase,m.round_number,
            count(*) as match_count,
            count(*) filter (where m.home_score=m.away_score) as draws
        from public.athlth_tournament_matches m
        join public.athlth_tournaments t on t.id=m.tournament_id
        where t.competition_settings_applied
          and t.status in ('active','completed')
          and m.phase<>'warmup' and m.away_id is not null
        group by m.tournament_id,m.phase,m.round_number
        having bool_and(m.status='confirmed')
    loop
        v_message:='Runde '||v.round_number||' er ferdig: '||
            v.match_count||' godkjente oppgjør';
        if v.draws>0 then
            v_message:=v_message||', '||v.draws||' uavgjort';
        end if;
        v_message:=v_message||'. Se oppgjørene og den oppdaterte tabellen.';
        if private.athlth_competition_post_system(
            v.tournament_id,'round:'||v.phase||':'||v.round_number,
            v_message,false
        ) then v_count:=v_count+1; end if;
    end loop;

    -- Once per completed tournament: final result is in the linked detail.
    for v in
        select id from public.athlth_tournaments
        where competition_settings_applied and status='completed'
    loop
        if private.athlth_competition_post_system(
            v.id,'finished',
            'Konkurransen er ferdig. Se sluttresultat, plasseringer og eventuelle premier i oversikten.',
            true
        ) then v_count:=v_count+1; end if;
    end loop;

    -- Optional useful nudge: ONE private deadline warning per athlete and
    -- tournament per UTC day, never a wall of reminders in the group chat.
    for v_reminder in
        select distinct on (s.tournament_id,entry.user_id)
          s.tournament_id,entry.user_id,t.title,s.deadline_at
        from public.athlth_tournament_match_exercises s
        join public.athlth_tournament_matches m on m.id=s.match_id
        join public.athlth_tournaments t on t.id=s.tournament_id
        join public.athlth_tournament_entries entry
             on entry.tournament_id=t.id and entry.response='accepted'
             and entry.removed_at is null
             and entry.user_id in (m.home_id,m.away_id)
        where t.competition_settings_applied and t.status='active'
          and s.state='pending'
          and s.scheduled_at<=clock_timestamp()
          and s.deadline_at>clock_timestamp()
          and s.deadline_at<=clock_timestamp()+interval '3 hours'
          and not exists(
            select 1 from public.athlth_tournament_exercise_completions c
            where c.match_exercise_id=s.id and c.user_id=entry.user_id
              and c.review_status in ('approved','submitted')
          )
        order by s.tournament_id,entry.user_id,s.deadline_at
    loop
        insert into private.athlth_competition_notice_log(
            tournament_id,event_key
        ) values(
            v_reminder.tournament_id,
            'deadline:'||to_char(clock_timestamp() at time zone 'UTC','YYYYMMDD')
            ||':'||v_reminder.user_id::text
        ) on conflict do nothing;
        if found then
            insert into public.social_inbox_events(
                recipient_id,kind,title,message,entity_type,entity_id,actor_id
            ) values(
                v_reminder.user_id,'arena_round',
                left(v_reminder.title,80),
                'En øvelse nærmer seg fristen. Åpne konkurransen for å fullføre.',
                'athlth_tournament',v_reminder.tournament_id,null
            );
            v_count:=v_count+1;
        end if;
    end loop;

    return v_count;
end;
$fn$;
revoke all on function private.athlth_competition_publish_chat_digest()
    from public,anon,authenticated;

do $cron$
begin
    perform cron.schedule(
        'athlth-competition-chat-digest', '*/5 * * * *',
        'select private.athlth_competition_publish_chat_digest();'
    );
end;
$cron$;