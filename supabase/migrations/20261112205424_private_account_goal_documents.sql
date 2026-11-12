-- ATHLTH 2.1.9: private account-owned goals, not social profile goals.
-- Applied to ATHLTH Developer Supabase as migration 20261112205424.
-- Body includes user-entered targets/milestones and compact cover images.
-- Never store raw Apple Health samples here.
create table if not exists public.athlth_goal_documents (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 1 check (revision > 0),
  body_base64 text not null check (length(body_base64) between 1 and 8388608),
  updated_at timestamptz not null default now()
);
alter table public.athlth_goal_documents enable row level security;
revoke all on public.athlth_goal_documents from public, anon;
grant select, insert, update, delete on public.athlth_goal_documents to authenticated;

create policy "goal_document_owner_select" on public.athlth_goal_documents
  for select to authenticated using (user_id = (select auth.uid()));
create policy "goal_document_owner_insert" on public.athlth_goal_documents
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "goal_document_owner_update" on public.athlth_goal_documents
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "goal_document_owner_delete" on public.athlth_goal_documents
  for delete to authenticated using (user_id = (select auth.uid()));

create or replace function public.athlth_save_goal_document(
  p_expected_revision bigint,
  p_body_base64 text
) returns bigint language plpgsql security invoker
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_revision bigint;
begin
  if v_user_id is null then
    raise exception 'GOAL_AUTH_REQUIRED' using errcode = '28000';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'GOAL_INVALID_REVISION' using errcode = '22023';
  end if;
  if p_body_base64 is null or length(p_body_base64) < 1 or length(p_body_base64) > 8388608 then
    raise exception 'GOAL_INVALID_PAYLOAD' using errcode = '22023';
  end if;

  insert into public.athlth_goal_documents (user_id, revision, body_base64, updated_at)
  values (v_user_id, 1, p_body_base64, now())
  on conflict (user_id) do update
    set revision = athlth_goal_documents.revision + 1,
        body_base64 = excluded.body_base64,
        updated_at = now()
    where athlth_goal_documents.revision = p_expected_revision
  returning revision into v_revision;

  if v_revision is null then
    raise exception 'GOAL_SYNC_REVISION_CONFLICT' using errcode = '40001';
  end if;
  return v_revision;
end;
$$;
revoke all on function public.athlth_save_goal_document(bigint,text) from public, anon;
grant execute on function public.athlth_save_goal_document(bigint,text) to authenticated;

comment on table public.athlth_goal_documents is
  'Private account-owned goal snapshots and compact cover previews. No raw HealthKit samples.';
