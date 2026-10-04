alter table public.profile_social_settings
  alter column profile_visibility set default 'public',
  alter column discoverable set default true;

alter table public.social_profile_cards
  add column if not exists profile_visibility text not null default 'public'
    check (profile_visibility in ('private', 'friends', 'public'));

update public.social_profile_cards c
set profile_visibility = s.profile_visibility
from public.profile_social_settings s
where s.user_id = c.user_id
  and c.profile_visibility is distinct from s.profile_visibility;

create or replace function private.sync_profile_visibility_to_social_card()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  update public.social_profile_cards
  set profile_visibility = new.profile_visibility,
      updated_at = greatest(updated_at, now())
  where user_id = new.user_id;
  return new;
end;
$$;

revoke all on function private.sync_profile_visibility_to_social_card()
from public, anon, authenticated;

drop trigger if exists profile_social_settings_sync_card_visibility
on public.profile_social_settings;
create trigger profile_social_settings_sync_card_visibility
after insert or update of profile_visibility
on public.profile_social_settings
for each row execute function private.sync_profile_visibility_to_social_card();

create or replace function private.apply_profile_visibility_to_social_card()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  new.profile_visibility := coalesce(
    (select s.profile_visibility from public.profile_social_settings s where s.user_id = new.user_id),
    'public'
  );
  return new;
end;
$$;

revoke all on function private.apply_profile_visibility_to_social_card()
from public, anon, authenticated;

drop trigger if exists social_profile_cards_apply_visibility
on public.social_profile_cards;
create trigger social_profile_cards_apply_visibility
before insert on public.social_profile_cards
for each row execute function private.apply_profile_visibility_to_social_card();

drop policy if exists "users can follow from their own account"
on public.profile_follows;

create policy "users can follow public profiles from their own account"
on public.profile_follows
for insert
to authenticated
with check (
  (select auth.uid()) = follower_id
  and follower_id <> following_id
  and (
    coalesce(
      (select s.profile_visibility = 'public' from public.profile_social_settings s where s.user_id = following_id),
      false
    )
    or private.are_friends(following_id)
  )
);

create or replace function private.after_friend_request_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  a uuid;
  b uuid;
  sender_name text;
  recipient_name text;
begin
  if tg_op = 'INSERT' then
    select coalesce(display_name, username::text, 'Someone')
      into sender_name
    from public.social_profile_cards
    where user_id = new.sender_id;

    insert into public.social_inbox_events (
      recipient_id, kind, title, message, entity_type, entity_id
    )
    values (
      new.recipient_id,
      'friend_request',
      'New follow request',
      sender_name || ' wants to follow you on ATHLTH.',
      'friend_request',
      new.id
    );
    return new;
  end if;

  if old.status = 'pending' and new.status = 'accepted' then
    a := least(new.sender_id, new.recipient_id);
    b := greatest(new.sender_id, new.recipient_id);

    insert into public.friendships (user_a, user_b)
    values (a, b)
    on conflict (user_a, user_b) do nothing;

    insert into public.profile_follows (follower_id, following_id)
    values (new.sender_id, new.recipient_id)
    on conflict (follower_id, following_id) do nothing;

    select coalesce(display_name, username::text, 'This athlete')
      into recipient_name
    from public.social_profile_cards
    where user_id = new.recipient_id;

    insert into public.social_inbox_events (
      recipient_id, kind, title, message, entity_type, entity_id
    )
    values (
      new.sender_id,
      'friend_accepted',
      'Follow request accepted',
      recipient_name || ' accepted your follow request.',
      'friendship',
      new.id
    );
  end if;
  return new;
end;
$$;

revoke all on function private.after_friend_request_change()
from public, anon, authenticated;
