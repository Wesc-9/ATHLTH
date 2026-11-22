CREATE OR REPLACE FUNCTION private.athlth_competition_chat_notice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_title text;
begin
    if new.kind not in ('chat','announcement') then return new; end if;
    select title into v_title from public.athlth_tournaments
    where id=new.tournament_id;
    insert into public.social_inbox_events(
        recipient_id,kind,title,message,entity_type,entity_id,actor_id
    )
    select e.user_id,case when new.kind='announcement' then 'arena_round' else 'arena_chat' end,left(v_title,80),
        left(new.content,300),'athlth_tournament',new.tournament_id,
        new.author_id
    from public.athlth_tournament_entries e
    where e.tournament_id=new.tournament_id
      and e.response='accepted' and e.removed_at is null
      and e.user_id is distinct from new.author_id
      and (new.kind='announcement' or not exists(
          select 1 from public.social_inbox_events recent
          where recent.recipient_id=e.user_id
             and recent.entity_type='athlth_tournament'
             and recent.entity_id=new.tournament_id
             and recent.kind='arena_chat'
             and recent.created_at>clock_timestamp()-interval '60 seconds'
      ));
    return new;
end;
$function$
