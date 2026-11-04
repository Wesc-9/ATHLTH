-- Optional private plan-only sync for ATHLTH Studio.
-- Disabled by default. No HealthKit samples, GPS traces, recorded workouts,
-- readiness scores, or clinical measurements are stored by this feature.
create table if not exists public.studio_plan_sync_consents (
    user_id uuid primary key references auth.users(id) on delete cascade,
    enabled boolean not null default false,
    updated_at timestamptz not null default now()
);

create table if not exists public.studio_plan_documents (
    user_id uuid not null references auth.users(id) on delete cascade,
    plan_id uuid not null,
    revision bigint not null default 1 check (revision > 0),
    body_base64 text not null check (char_length(body_base64) between 1 and 2900000),
    updated_at timestamptz not null default now(),
    primary key (user_id, plan_id)
);

alter table public.studio_plan_sync_consents enable row level security;
alter table public.studio_plan_documents enable row level security;

create policy studio_plan_consent_select on public.studio_plan_sync_consents
    for select to authenticated using (user_id = (select auth.uid()));
create policy studio_plan_consent_insert on public.studio_plan_sync_consents
    for insert to authenticated with check (user_id = (select auth.uid()));
create policy studio_plan_consent_update on public.studio_plan_sync_consents
    for update to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));
create policy studio_plan_consent_delete on public.studio_plan_sync_consents
    for delete to authenticated using (user_id = (select auth.uid()));

create policy studio_plan_docs_select on public.studio_plan_documents
    for select to authenticated using (
        user_id = (select auth.uid()) and
        exists (
          select 1 from public.studio_plan_sync_consents c
          where c.user_id = (select auth.uid()) and c.enabled
        )
    );
create policy studio_plan_docs_insert on public.studio_plan_documents
    for insert to authenticated with check (
        user_id = (select auth.uid()) and
        exists (
          select 1 from public.studio_plan_sync_consents c
          where c.user_id = (select auth.uid()) and c.enabled
        )
    );
create policy studio_plan_docs_update on public.studio_plan_documents
    for update to authenticated using (
        user_id = (select auth.uid()) and
        exists (
          select 1 from public.studio_plan_sync_consents c
          where c.user_id = (select auth.uid()) and c.enabled
        )
    ) with check (
        user_id = (select auth.uid()) and
        exists (
          select 1 from public.studio_plan_sync_consents c
          where c.user_id = (select auth.uid()) and c.enabled
        )
    );
create policy studio_plan_docs_delete on public.studio_plan_documents
    for delete to authenticated using (
        user_id = (select auth.uid()) and
        exists (
          select 1 from public.studio_plan_sync_consents c
          where c.user_id = (select auth.uid()) and c.enabled
        )
    );

revoke all on public.studio_plan_sync_consents from anon;
revoke all on public.studio_plan_documents from anon;
grant select, insert, update, delete on public.studio_plan_sync_consents to authenticated;
grant select, insert, update, delete on public.studio_plan_documents to authenticated;

-- Atomic compare-and-set avoids last-writer-wins when two devices edit one plan.
create or replace function public.studio_save_plan(
    p_plan_id uuid,
    p_expected_revision bigint,
    p_body_base64 text
) returns bigint
language plpgsql security invoker
set search_path = public, pg_temp
as $$
declare
    v_uid uuid := (select auth.uid());
    v_revision bigint;
begin
    if v_uid is null then
        raise exception 'Not authenticated' using errcode = '28000';
    end if;
    if p_plan_id is null or p_expected_revision is null or
       p_expected_revision < 0 or p_body_base64 is null or
       char_length(p_body_base64) < 1 or char_length(p_body_base64) > 2900000 then
        raise exception 'Invalid plan document' using errcode = '22023';
    end if;
    if not exists (
        select 1 from public.studio_plan_sync_consents
        where user_id = v_uid and enabled
    ) then
        raise exception 'Plan synchronization consent required' using errcode = '42501';
    end if;

    insert into public.studio_plan_documents (
        user_id, plan_id, revision, body_base64, updated_at
    ) values (
        v_uid, p_plan_id, 1, p_body_base64, now()
    )
    on conflict (user_id, plan_id) do update
        set revision = public.studio_plan_documents.revision + 1,
            body_base64 = excluded.body_base64,
            updated_at = now()
        where public.studio_plan_documents.revision = p_expected_revision
    returning revision into v_revision;

    if v_revision is null then
        raise exception 'Plan revision conflict' using errcode = 'P0001';
    end if;
    return v_revision;
end;
$$;

revoke all on function public.studio_save_plan(uuid, bigint, text) from public, anon;
grant execute on function public.studio_save_plan(uuid, bigint, text) to authenticated;
