-- Account-owned plan synchronization without a separate optional toggle.
-- Staged migration: review lawful basis, sensitive plan notes, notice, RLS,
-- and legacy opt-outs before deploying. This does not alter existing backup
-- or Coach permissions.
begin;
alter table public.studio_plan_documents enable row level security;
-- Preserve old explicit opt-outs. New account-owned documents need no
-- separate plan-sync permission record.
drop policy if exists studio_plan_docs_select on public.studio_plan_documents;
drop policy if exists studio_plan_docs_insert on public.studio_plan_documents;
drop policy if exists studio_plan_docs_update on public.studio_plan_documents;
drop policy if exists studio_plan_docs_delete on public.studio_plan_documents;

create policy studio_plan_docs_select on public.studio_plan_documents
    for select to authenticated using (
        user_id = (select auth.uid()) and
        not exists (
            select 1 from public.studio_plan_sync_consents c
            where c.user_id = (select auth.uid()) and not c.enabled
        )
    );
create policy studio_plan_docs_insert on public.studio_plan_documents
    for insert to authenticated with check (
        user_id = (select auth.uid()) and
        not exists (
            select 1 from public.studio_plan_sync_consents c
            where c.user_id = (select auth.uid()) and not c.enabled
        )
    );
create policy studio_plan_docs_update on public.studio_plan_documents
    for update to authenticated
    using (user_id = (select auth.uid()) and
        not exists (
            select 1 from public.studio_plan_sync_consents c
            where c.user_id = (select auth.uid()) and not c.enabled
        ))
    with check (user_id = (select auth.uid()) and
        not exists (
            select 1 from public.studio_plan_sync_consents c
            where c.user_id = (select auth.uid()) and not c.enabled
        ));
create policy studio_plan_docs_delete on public.studio_plan_documents
    for delete to authenticated using (user_id = (select auth.uid()));

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
    -- Historical opt-outs remain binding across all devices.
    if exists (
        select 1 from public.studio_plan_sync_consents
        where user_id = v_uid and not enabled
    ) then
        raise exception 'Legacy plan synchronization opt-out' using errcode = '42501';
    end if;

    -- A deleted row cannot be resurrected by a stale device expecting
    -- a nonzero revision. Insert and update are deliberately separate.
    if p_expected_revision = 0 then
        insert into public.studio_plan_documents (
            user_id, plan_id, revision, body_base64, updated_at
        ) values (
            v_uid, p_plan_id, 1, p_body_base64, now()
        )
        on conflict (user_id, plan_id) do nothing
        returning revision into v_revision;
    else
        update public.studio_plan_documents
        set revision = revision + 1,
            body_base64 = p_body_base64,
            updated_at = now()
        where user_id = v_uid and plan_id = p_plan_id
          and revision = p_expected_revision
        returning revision into v_revision;
    end if;

    if v_revision is null then
        raise exception 'Plan revision conflict' using errcode = 'P0001';
    end if;
    return v_revision;
end;
$$;

revoke all on function public.studio_save_plan(uuid, bigint, text) from public, anon;

grant execute on function public.studio_save_plan(uuid, bigint, text) to authenticated;
commit;
