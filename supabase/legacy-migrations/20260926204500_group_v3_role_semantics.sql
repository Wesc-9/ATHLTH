-- Tighten the v3 role semantics:
-- Contributor has update publishing as its only elevated permission.
-- When member-created content is enabled, Contributor participates like any
-- other member. @everyone remains Owner/Admin only.

create or replace function private.can_create_community_group_content(
  p_group_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
    select 1
    from public.community_groups g
    left join public.community_group_members gm
      on gm.group_id = g.id
     and gm.user_id = p_user_id
    where g.id = p_group_id
      and (
        g.creator_id = p_user_id
        or gm.role in ('owner', 'admin')
        or (
          gm.role in ('member', 'contributor')
          and g.members_can_create_content = true
        )
      )
  );
$$;

create or replace function private.after_community_group_message_notify()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  group_name text;
  sender_label text;
  sender_role text;
  mention_tokens text[];
  everyone_tagged boolean := false;
  target record;
  target_mentioned boolean;
  mode text;
begin
  select g.name into group_name
  from public.community_groups g
  where g.id = new.group_id;

  select
    coalesce(nullif(p.username::text, ''), nullif(p.display_name, ''), 'A member')
  into sender_label
  from public.profiles p
  where p.id = new.sender_id;

  sender_role := private.community_group_role(new.group_id, new.sender_id);

  select array_agg(distinct lower(m[1]))
    into mention_tokens
  from regexp_matches(
    lower(new.body),
    '@([a-z0-9._-]+)',
    'g'
  ) as m;

  mention_tokens := coalesce(mention_tokens, array[]::text[]);

  everyone_tagged :=
    (
      'everyone' = any(mention_tokens)
      or 'all' = any(mention_tokens)
      or 'alle' = any(mention_tokens)
    )
    and sender_role in ('owner', 'admin');

  for target in
    select gm.user_id, p.username::text as username
    from public.community_group_members gm
    left join public.profiles p on p.id = gm.user_id
    where gm.group_id = new.group_id
      and gm.user_id <> new.sender_id
  loop
    target_mentioned :=
      everyone_tagged
      or (
        target.username is not null
        and lower(target.username) = any(mention_tokens)
      );

    mode := private.community_group_notification_mode(
      new.group_id,
      target.user_id
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
        '@' || coalesce(sender_label, 'A member') ||
          ' mentioned you in ' || coalesce(group_name, 'a group') || '.',
        'community_group_message',
        new.id,
        new.group_id
      );
    elsif mode = 'all' then
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
        'group_message',
        coalesce(group_name, 'Group'),
        coalesce(sender_label, 'A member') || ': ' || left(new.body, 220),
        'community_group_message',
        new.id,
        new.group_id
      );
    end if;
  end loop;

  return new;
end;
$$;

revoke all on function private.can_create_community_group_content(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.after_community_group_message_notify()
  from public, anon, authenticated;
