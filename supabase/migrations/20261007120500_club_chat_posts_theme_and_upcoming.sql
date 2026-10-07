-- ATHLTH 1.6.7: Club chat images, post comments, and per-Club color themes.
-- Additive/backward-compatible migration.

alter table public.community_groups
  add column if not exists theme_key text not null default 'emerald';

alter table public.community_groups
  drop constraint if exists community_groups_theme_key_check;

alter table public.community_groups
  add constraint community_groups_theme_key_check
  check (
    theme_key in (
      'emerald',
      'ocean',
      'cobalt',
      'violet',
      'sunset',
      'ruby',
      'graphite'
    )
  );

alter table public.community_group_messages
  add column if not exists image_url text;

alter table public.community_group_messages
  alter column body set default '';

alter table public.community_group_messages
  drop constraint if exists community_group_messages_body_check;

alter table public.community_group_messages
  add constraint community_group_messages_body_check
  check (
    char_length(trim(body)) <= 2000
    and (
      char_length(trim(body)) > 0
      or nullif(trim(image_url), '') is not null
    )
  );

alter table public.community_group_content_comments
  drop constraint if exists community_group_content_comments_content_type_check;

alter table public.community_group_content_comments
  add constraint community_group_content_comments_content_type_check
  check (content_type in ('event','challenge','announcement'));

create or replace function private.community_group_content_exists(
  p_group_id uuid,
  p_content_type text,
  p_content_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select case
    when p_content_type = 'event' then exists (
      select 1
      from public.community_group_events e
      where e.id = p_content_id
        and e.group_id = p_group_id
    )
    when p_content_type = 'challenge' then exists (
      select 1
      from public.community_group_challenges c
      where c.id = p_content_id
        and c.group_id = p_group_id
    )
    when p_content_type = 'announcement' then exists (
      select 1
      from public.community_group_announcements a
      where a.id = p_content_id
        and a.group_id = p_group_id
    )
    else false
  end;
$$;

create or replace function private.can_manage_community_group_content(
  p_group_id uuid,
  p_content_type text,
  p_content_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select
    private.can_manage_community_group(p_group_id)
    or case
      when p_content_type = 'event' then exists (
        select 1
        from public.community_group_events e
        where e.id = p_content_id
          and e.group_id = p_group_id
          and e.creator_id = p_user_id
      )
      when p_content_type = 'challenge' then exists (
        select 1
        from public.community_group_challenges c
        where c.id = p_content_id
          and c.group_id = p_group_id
          and c.creator_id = p_user_id
      )
      when p_content_type = 'announcement' then exists (
        select 1
        from public.community_group_announcements a
        where a.id = p_content_id
          and a.group_id = p_group_id
          and a.author_id = p_user_id
      )
      else false
    end;
$$;

create or replace function private.after_community_group_content_comment_notify()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  author_label text;
  content_title text;
  mention_tokens text[];
  target record;
begin
  select coalesce(
    nullif(p.username::text, ''),
    nullif(p.display_name, ''),
    'A group member'
  )
  into author_label
  from public.profiles p
  where p.id = new.author_id;

  if new.content_type = 'event' then
    select e.title into content_title
    from public.community_group_events e
    where e.id = new.content_id;
  elsif new.content_type = 'challenge' then
    select c.title into content_title
    from public.community_group_challenges c
    where c.id = new.content_id;
  else
    content_title := 'Club post';
  end if;

  select array_agg(distinct lower(m[1]))
  into mention_tokens
  from regexp_matches(
    lower(new.body),
    '@([a-z0-9._-]+)',
    'g'
  ) as m;

  mention_tokens := coalesce(
    mention_tokens,
    array[]::text[]
  );

  for target in
    select gm.user_id, p.username::text as username
    from public.community_group_members gm
    join public.profiles p
      on p.id = gm.user_id
    where gm.group_id = new.group_id
      and gm.user_id <> new.author_id
      and p.username is not null
  loop
    if lower(target.username) = any(mention_tokens)
       and private.mention_notifications_enabled(target.user_id)
    then
      insert into public.social_inbox_events(
        recipient_id,
        kind,
        title,
        message,
        entity_type,
        entity_id,
        group_id
      )
      values (
        target.user_id,
        'mention',
        'You were mentioned',
        '@' || coalesce(author_label, 'A member') ||
          ' mentioned you in ' ||
          coalesce(content_title, 'group content') || '.',
        'community_group_content_comment',
        new.id,
        new.group_id
      );
    end if;
  end loop;

  return new;
end;
$$;

revoke all on function private.community_group_content_exists(uuid,text,uuid)
  from public, anon, authenticated;
revoke all on function private.can_manage_community_group_content(uuid,text,uuid,uuid)
  from public, anon, authenticated;
revoke all on function private.after_community_group_content_comment_notify()
  from public, anon, authenticated;
