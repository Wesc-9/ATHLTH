-- ATHLTH 1.6.7: support @everyone/@all/@alle in Club post comments.

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
  mention_everyone boolean := false;
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

  mention_everyone :=
    'everyone' = any(mention_tokens)
    or 'all' = any(mention_tokens)
    or 'alle' = any(mention_tokens);

  for target in
    select gm.user_id, p.username::text as username
    from public.community_group_members gm
    left join public.profiles p
      on p.id = gm.user_id
    where gm.group_id = new.group_id
      and gm.user_id <> new.author_id
  loop
    if (
         mention_everyone
         or (
           target.username is not null
           and lower(target.username) = any(mention_tokens)
         )
       )
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

revoke all on function private.after_community_group_content_comment_notify()
from public, anon, authenticated;
