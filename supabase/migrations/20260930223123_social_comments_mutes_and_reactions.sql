alter table public.social_activity_reactions
  drop constraint if exists social_activity_reactions_reaction_check;

alter table public.social_activity_reactions
  add constraint social_activity_reactions_reaction_check
  check (reaction in ('fire', 'strong', 'clap', 'heart'));

create table if not exists public.social_activity_comments (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.social_activities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 280),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists social_activity_comments_activity_created_idx
  on public.social_activity_comments(activity_id, created_at asc);

create index if not exists social_activity_comments_user_idx
  on public.social_activity_comments(user_id, created_at desc);

alter table public.social_activity_comments enable row level security;

revoke all on table public.social_activity_comments from anon, authenticated;
grant select, insert, update, delete on table public.social_activity_comments to authenticated;

drop policy if exists social_activity_comments_select_visible on public.social_activity_comments;
create policy social_activity_comments_select_visible
on public.social_activity_comments
for select
to authenticated
using (
  exists (
    select 1
    from public.social_activities a
    where a.id = social_activity_comments.activity_id
      and private.can_view_activity(a.actor_id, a.visibility, a.kind, a.metadata)
  )
);

drop policy if exists social_activity_comments_insert_visible on public.social_activity_comments;
create policy social_activity_comments_insert_visible
on public.social_activity_comments
for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and exists (
    select 1
    from public.social_activities a
    where a.id = social_activity_comments.activity_id
      and private.can_view_activity(a.actor_id, a.visibility, a.kind, a.metadata)
  )
);

drop policy if exists social_activity_comments_update_own on public.social_activity_comments;
create policy social_activity_comments_update_own
on public.social_activity_comments
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists social_activity_comments_delete_own_or_activity_owner on public.social_activity_comments;
create policy social_activity_comments_delete_own_or_activity_owner
on public.social_activity_comments
for delete
to authenticated
using (
  (select auth.uid()) = user_id
  or exists (
    select 1
    from public.social_activities a
    where a.id = social_activity_comments.activity_id
      and a.actor_id = (select auth.uid())
  )
);

create table if not exists public.social_user_mutes (
  muter_id uuid not null references public.profiles(id) on delete cascade,
  muted_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (muter_id, muted_id),
  check (muter_id <> muted_id)
);

create index if not exists social_user_mutes_muted_idx
  on public.social_user_mutes(muted_id);

alter table public.social_user_mutes enable row level security;

revoke all on table public.social_user_mutes from anon, authenticated;
grant select, insert, delete on table public.social_user_mutes to authenticated;

drop policy if exists social_user_mutes_select_own on public.social_user_mutes;
create policy social_user_mutes_select_own
on public.social_user_mutes
for select
to authenticated
using ((select auth.uid()) = muter_id);

drop policy if exists social_user_mutes_insert_own on public.social_user_mutes;
create policy social_user_mutes_insert_own
on public.social_user_mutes
for insert
to authenticated
with check (
  (select auth.uid()) = muter_id
  and muter_id <> muted_id
);

drop policy if exists social_user_mutes_delete_own on public.social_user_mutes;
create policy social_user_mutes_delete_own
on public.social_user_mutes
for delete
to authenticated
using ((select auth.uid()) = muter_id);
