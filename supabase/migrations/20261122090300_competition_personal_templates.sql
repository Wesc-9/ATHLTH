create table if not exists public.athlth_tournament_templates(
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(length(btrim(name)) between 2 and 80),
 payload text not null check(length(payload) between 16 and 150000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(owner_id,name)
);
alter table public.athlth_tournament_templates enable row level security;
grant select,insert,update,delete on public.athlth_tournament_templates to authenticated;
drop policy if exists tournament_templates_select_own on public.athlth_tournament_templates;
create policy tournament_templates_select_own on public.athlth_tournament_templates
for select to authenticated using(owner_id=(select auth.uid()));
drop policy if exists tournament_templates_insert_own on public.athlth_tournament_templates;
create policy tournament_templates_insert_own on public.athlth_tournament_templates
for insert to authenticated with check(owner_id=(select auth.uid()));
drop policy if exists tournament_templates_update_own on public.athlth_tournament_templates;
create policy tournament_templates_update_own on public.athlth_tournament_templates
for update to authenticated using(owner_id=(select auth.uid()))
with check(owner_id=(select auth.uid()));
drop policy if exists tournament_templates_delete_own on public.athlth_tournament_templates;
create policy tournament_templates_delete_own on public.athlth_tournament_templates
for delete to authenticated using(owner_id=(select auth.uid()));