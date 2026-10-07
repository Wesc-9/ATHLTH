-- ATHLTH 1.6.7: @mentions in Club posts.
-- Mentioned members receive a mention inbox event instead of a duplicate generic Club update.

create or replace function private.after_community_group_announcement_notify()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  group_name text;
  author_label text;
  mention_tokens text[];
  mention_everyone boolean := false;
  target record;
  mode text;
  target_mentioned boolean;
begin
  select g.name into group_name
  from public.community_groups g
  where g.id = new.group_id;

  select coalesce(
    nullif(p.username::text, ''),
    nullif(p.display_name, ''),
    'A Club member'
  )
  into author_label
  from public.profiles p
  where p.id = new.author_id;

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

  mention_everyone :=
    'everyone' = any(mention_tokens)
    or 'all' = any(mention_tokens)
    or 'alle' = any(mention_tokens);

  for target in
    select
      gm.user_id,
      p.username::text as username
    from public.community_group_members gm
    left join public.profiles p
      on p.id = gm.user_id
    where gm.group_id = new.group_id
      and gm.user_id <> new.author_id
  loop
    mode := private.community_group_notification_mode(
      new.group_id,
      target.user_id
    );

    target_mentioned :=
      mention_everyone
      or (
        target.username is not null
        and lower(target.username) = any(mention_tokens)
      );

    if target_mentioned
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
        '@' || coalesce(author_label, 'A Club member') ||
          ' mentioned you in ' ||
          coalesce(group_name, 'a Club') || '.',
        'community_group_announcement',
        new.id,
        new.group_id
      );
    elsif mode in ('all', 'important') then
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
        'group_update',
        coalesce(group_name, 'Club') || ' update',
        left(new.body, 240),
        'community_group_announcement',
        new.id,
        new.group_id
      );
    end if;
  end loop;

  return new;
end;
$$;

revoke all on function private.after_community_group_announcement_notify()
from public, anon, authenticated;
