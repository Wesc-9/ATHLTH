-- Dedicated Community event chat, organizer status updates and explicit lifecycle.
-- ATHLTH 1.6.6 / step 3.

alter table public.community_events
  drop constraint if exists community_events_status_check;

alter table public.community_events
  add constraint community_events_status_check
  check (
    status in (
      'upcoming',
      'live',
      'cancelled',
      'completed'
    )
  );

create table if not exists public.community_event_messages (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null
    references public.community_events(id)
    on delete cascade,
  author_id uuid
    references public.profiles(id)
    on delete set null,
  kind text not null default 'message'
    check (kind in ('message','status','system')),
  body text not null
    check (
      char_length(btrim(body)) between 1 and 2000
    ),
  created_at timestamptz not null default now()
);

create index if not exists community_event_messages_event_created_idx
  on public.community_event_messages (event_id, created_at);

create index if not exists community_event_messages_author_idx
  on public.community_event_messages (author_id)
  where author_id is not null;

alter table public.community_event_messages
  enable row level security;

revoke all on table public.community_event_messages from anon;
grant select, insert
  on table public.community_event_messages
  to authenticated;

drop policy if exists community_event_messages_select_member
  on public.community_event_messages;

create policy community_event_messages_select_member
  on public.community_event_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.community_events e
      where e.id = community_event_messages.event_id
        and (
          e.creator_id = (select auth.uid())
          or exists (
            select 1
            from public.community_event_participants p
            where p.event_id = e.id
              and p.user_id = (select auth.uid())
          )
        )
    )
  );

drop policy if exists community_event_messages_insert_member
  on public.community_event_messages;

create policy community_event_messages_insert_member
  on public.community_event_messages
  for insert
  to authenticated
  with check (
    author_id = (select auth.uid())
    and exists (
      select 1
      from public.community_events e
      where e.id = community_event_messages.event_id
        and e.status in ('upcoming','live')
        and (
          e.creator_id = (select auth.uid())
          or exists (
            select 1
            from public.community_event_participants p
            where p.event_id = e.id
              and p.user_id = (select auth.uid())
          )
        )
        and (
          community_event_messages.kind = 'message'
          or (
            community_event_messages.kind in ('status','system')
            and e.creator_id = (select auth.uid())
          )
        )
    )
  );

create or replace function public.community_event_set_lifecycle(
  p_event_id uuid,
  p_status text
)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_creator uuid;
  v_current text;
  v_system_body text;
begin
  if p_status not in ('live','completed','cancelled') then
    raise exception 'Unsupported event lifecycle status';
  end if;

  select creator_id, status
    into v_creator, v_current
  from public.community_events
  where id = p_event_id
  for update;

  if v_creator is null then
    raise exception 'Event not found';
  end if;

  if v_creator <> (select auth.uid()) then
    raise exception 'Only the organizer can change event status';
  end if;

  if v_current in ('completed','cancelled') then
    if v_current = p_status then
      return v_current;
    end if;

    raise exception 'A closed event cannot change status';
  end if;

  if p_status = 'live' and v_current <> 'upcoming' then
    raise exception 'Only a planned event can be started';
  end if;

  update public.community_events
  set
    status = p_status,
    updated_at = now()
  where id = p_event_id;

  v_system_body :=
    case p_status
      when 'live' then 'event_started'
      when 'completed' then 'event_completed'
      when 'cancelled' then 'event_cancelled'
      else null
    end;

  if v_system_body is not null then
    insert into public.community_event_messages (
      event_id,
      author_id,
      kind,
      body
    )
    values (
      p_event_id,
      (select auth.uid()),
      'system',
      v_system_body
    );
  end if;

  return p_status;
end;
$$;

revoke all on function public.community_event_set_lifecycle(uuid, text)
  from public;

grant execute
  on function public.community_event_set_lifecycle(uuid, text)
  to authenticated;
