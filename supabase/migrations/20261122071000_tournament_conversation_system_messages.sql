-- One private, idempotent system timeline for every real tournament chat.
-- All push notices reuse existing social inbox events and its APNs trigger.
alter table public.athlth_tournament_lobby_messages
    alter column author_id drop not null;
alter table public.athlth_tournament_lobby_messages
    drop constraint if exists athlth_tournament_lobby_messages_kind_check;
alter table public.athlth_tournament_lobby_messages
    add constraint athlth_tournament_lobby_messages_kind_check
    check (kind in ('chat','announcement','system'));

create table if not exists private.athlth_competition_notice_log (
    tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
    event_key text not null check(length(event_key) between 1 and 160),
    created_at timestamptz not null default clock_timestamp(),
    primary key(tournament_id,event_key)
);
alter table private.athlth_competition_notice_log enable row level security;
revoke all on private.athlth_competition_notice_log from public,anon,authenticated;
create index if not exists athlth_tournament_lobby_messages_latest
    on public.athlth_tournament_lobby_messages(tournament_id,created_at desc);

-- Called only from trusted database triggers/cron. Unique keys prevent
-- duplicate timeline messages, even if a worker runs twice concurrently.
create or replace function private.athlth_competition_post_system(
    p_tournament uuid, p_key text, p_body text, p_push boolean default true
) returns boolean language plpgsql security definer
set search_path='' as $fn$
declare v_t public.athlth_tournaments%rowtype;
begin
    select * into v_t from public.athlth_tournaments
    where id=p_tournament;
    if not found or length(btrim(coalesce(p_body,''))) not between 1 and 1000
       or length(p_key) not between 1 and 160 then
       return false;
    end if;
    insert into private.athlth_competition_notice_log(
        tournament_id,event_key
    ) values(p_tournament,p_key)
    on conflict do nothing;
    if not found then return false; end if;

    insert into public.athlth_tournament_lobby_messages(
        tournament_id,author_id,content,kind
    ) values(p_tournament,null,btrim(p_body),'system');

    if p_push then
        insert into public.social_inbox_events(
            recipient_id,kind,title,message,entity_type,entity_id,actor_id
        )
        select e.user_id,'arena_round',left(v_t.title,80),
               left(p_body,300),'athlth_tournament',p_tournament,null
        from public.athlth_tournament_entries e
        where e.tournament_id=p_tournament and e.response='accepted'
            and e.removed_at is null;
    end if;
    return true;
end;
$fn$;
revoke all on function private.athlth_competition_post_system(uuid,text,text,boolean)
    from public,anon,authenticated;

-- The invitations appear individually in Inbox, while they all lead to the
-- same tournament chat. Send once after the new full rule package is saved.
create or replace function private.athlth_competition_invitation_initialized()
returns trigger language plpgsql security definer
set search_path='' as $fn$
begin
    if not old.competition_settings_applied and new.competition_settings_applied then
        perform private.athlth_competition_post_system(
            new.id,'created',
            'Konkurransen er opprettet. Se regler og deltakere i oversikten. Inviterte kan godta eller avslå her.',
            false
        );
        insert into public.social_inbox_events(
            recipient_id,kind,title,message,entity_type,entity_id,actor_id
        )
        select e.user_id,'arena_invite',left(new.title,80),
            'Du er invitert til '||left(new.title,80)||'. Åpne samtalen og svar.',
            'athlth_tournament',new.id,new.owner_id
        from public.athlth_tournament_entries e
        where e.tournament_id=new.id and e.response='invited'
          and e.removed_at is null;
    end if;
    return new;
end;
$fn$;
drop trigger if exists athlth_competition_invitation_initialized
on public.athlth_tournaments;
create trigger athlth_competition_invitation_initialized
after update of competition_settings_applied on public.athlth_tournaments
for each row execute function private.athlth_competition_invitation_initialized();
revoke all on function private.athlth_competition_invitation_initialized()
    from public,anon,authenticated;

-- Additional invites from the approved member/admin flow need their
-- own targeted invitation notification (not a new group chat).
create or replace function private.athlth_competition_new_invitee()
returns trigger language plpgsql security definer
set search_path='' as $fn$
declare v_t public.athlth_tournaments%rowtype;
begin
    if new.response<>'invited' then return new; end if;
    select * into v_t from public.athlth_tournaments
    where id=new.tournament_id;
    if not found or not v_t.competition_settings_applied then return new; end if;
    insert into public.social_inbox_events(
        recipient_id,kind,title,message,entity_type,entity_id,actor_id
    ) values(
        new.user_id,'arena_invite',left(v_t.title,80),
        'Du er invitert til '||left(v_t.title,80)||'. Åpne samtalen og svar.',
        'athlth_tournament',v_t.id,v_t.owner_id
    );
    return new;
end;
$fn$;
drop trigger if exists athlth_competition_new_invitee
on public.athlth_tournament_entries;
create trigger athlth_competition_new_invitee
after insert on public.athlth_tournament_entries
for each row execute function private.athlth_competition_new_invitee();
revoke all on function private.athlth_competition_new_invitee()
    from public,anon,authenticated;

-- Chat messages are normal messages. Never send a second push for an
-- automatically inserted system update, and throttle chatter per recipient.
create or replace function private.athlth_competition_chat_notice()
returns trigger language plpgsql security definer
set search_path='' as $fn$
declare v_title text;
begin
    if new.kind not in ('chat','announcement') then return new; end if;
    select title into v_title from public.athlth_tournaments
    where id=new.tournament_id;
    insert into public.social_inbox_events(
        recipient_id,kind,title,message,entity_type,entity_id,actor_id
    )
    select e.user_id,'arena_chat',left(v_title,80),
        left(new.content,300),'athlth_tournament',new.tournament_id,
        new.author_id
    from public.athlth_tournament_entries e
    where e.tournament_id=new.tournament_id
      and e.response='accepted' and e.removed_at is null
      and e.user_id is distinct from new.author_id
      and not exists(
          select 1 from public.social_inbox_events recent
          where recent.recipient_id=e.user_id
             and recent.entity_type='athlth_tournament'
             and recent.entity_id=new.tournament_id
             and recent.kind='arena_chat'
             and recent.created_at>clock_timestamp()-interval '60 seconds'
      );
    return new;
end;
$fn$;
drop trigger if exists athlth_competition_chat_notice
on public.athlth_tournament_lobby_messages;
create trigger athlth_competition_chat_notice
after insert on public.athlth_tournament_lobby_messages
for each row execute function private.athlth_competition_chat_notice();
revoke all on function private.athlth_competition_chat_notice()
    from public,anon,authenticated;