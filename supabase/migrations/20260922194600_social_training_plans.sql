create table if not exists public.social_training_plans (
  id uuid primary key,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  summary text not null default '',
  visibility text not null default 'private'
    check (visibility in ('private','friends','public')),
  version integer not null default 1 check (version >= 1),
  plan jsonb not null,
  copied_from_plan_id uuid references public.social_training_plans(id) on delete set null,
  published_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists social_training_plans_owner_idx
  on public.social_training_plans(owner_id, updated_at desc);
create index if not exists social_training_plans_visibility_idx
  on public.social_training_plans(visibility, updated_at desc);
create index if not exists social_training_plans_copied_from_idx
  on public.social_training_plans(copied_from_plan_id)
  where copied_from_plan_id is not null;

create table if not exists public.social_training_plan_follows (
  user_id uuid not null references public.profiles(id) on delete cascade,
  plan_id uuid not null references public.social_training_plans(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, plan_id)
);

create index if not exists social_training_plan_follows_plan_idx
  on public.social_training_plan_follows(plan_id, created_at desc);

alter table public.social_training_plans enable row level security;
alter table public.social_training_plan_follows enable row level security;

revoke all on table public.social_training_plans from anon, authenticated;
revoke all on table public.social_training_plan_follows from anon, authenticated;

grant select, insert, update, delete on public.social_training_plans to authenticated;
grant select, insert, delete on public.social_training_plan_follows to authenticated;

create or replace function private.can_view_training_plan(plan_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
    select 1
    from public.social_training_plans p
    where p.id = plan_uuid
      and (
        p.owner_id = (select auth.uid())
        or (p.visibility = 'public' and not private.is_blocked(p.owner_id))
        or (
          p.visibility = 'friends'
          and private.are_friends(p.owner_id)
          and not private.is_blocked(p.owner_id)
        )
      )
  );
$$;

revoke all on function private.can_view_training_plan(uuid) from public, anon;
grant execute on function private.can_view_training_plan(uuid) to authenticated;

create policy social_training_plans_select_allowed
on public.social_training_plans for select
to authenticated
using (
  owner_id = (select auth.uid())
  or (visibility = 'public' and not private.is_blocked(owner_id))
  or (
    visibility = 'friends'
    and private.are_friends(owner_id)
    and not private.is_blocked(owner_id)
  )
);

create policy social_training_plans_insert_owner
on public.social_training_plans for insert
to authenticated
with check (owner_id = (select auth.uid()));

create policy social_training_plans_update_owner
on public.social_training_plans for update
to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

create policy social_training_plans_delete_owner
on public.social_training_plans for delete
to authenticated
using (owner_id = (select auth.uid()));

create policy social_training_plan_follows_select_own
on public.social_training_plan_follows for select
to authenticated
using (user_id = (select auth.uid()));

create policy social_training_plan_follows_insert_own
on public.social_training_plan_follows for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and private.can_view_training_plan(plan_id)
  and not exists (
    select 1
    from public.social_training_plans p
    where p.id = plan_id
      and p.owner_id = (select auth.uid())
  )
);

create policy social_training_plan_follows_delete_own
on public.social_training_plan_follows for delete
to authenticated
using (user_id = (select auth.uid()));

create trigger social_training_plans_updated_at
before update on public.social_training_plans
for each row execute function public.set_updated_at();
