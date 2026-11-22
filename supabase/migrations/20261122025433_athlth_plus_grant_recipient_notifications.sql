-- Inform the recipient only after a successful complimentary ATHLTH+ grant.
-- Uses the existing recipient-scoped social inbox + APNs pipeline, never the
-- grantor's device or an unverified client-side success banner.
--
-- Keep every previously allowed inbox kind when adding the distinct system
-- event type. The existing constraint may have been extended by other
-- community features after its original migration.
do $migration$
declare
    previous_check text;
begin
    select pg_catalog.pg_get_constraintdef(c.oid)
      into previous_check
      from pg_catalog.pg_constraint c
     where c.conrelid = 'public.social_inbox_events'::pg_catalog.regclass
       and c.conname = 'social_inbox_events_kind_check';

    if previous_check is null or left(previous_check, 7) <> 'CHECK (' then
        raise exception 'Missing expected social inbox kind constraint';
    end if;

    if position('athlth_plus_granted' in previous_check) = 0 then
        alter table public.social_inbox_events
            drop constraint social_inbox_events_kind_check;
        execute 'alter table public.social_inbox_events add constraint ' ||
            'social_inbox_events_kind_check ' ||
            left(previous_check, length(previous_check) - 1) ||
            ' OR kind = ''athlth_plus_granted'')';
    end if;
end;
$migration$;

create or replace function private.athlth_notify_plus_grant_recipient()
returns trigger
language plpgsql
security definer
set search_path = ''
as $body$
declare
    v_days integer;
    v_message text;
begin
    -- Revocation and unrelated updates are not new gifts.
    if new.revoked_at is not null then
        return new;
    end if;
    if tg_op = 'UPDATE' then
        if new.granted_at is not distinct from old.granted_at
           and new.expires_at is not distinct from old.expires_at
           and old.revoked_at is null then
            return new;
        end if;
    end if;

    if new.expires_at is null then
        v_message := 'You have received ATHLTH+ with no end date.';
    else
        -- The administrator's allowed choices are whole-day grants. Round
        -- to account for the tiny difference between the two server clock
        -- calls in the existing grant RPC.
        v_days := greatest(1, round(
            extract(epoch from (new.expires_at - new.granted_at)) / 86400
        )::integer);
        v_message := 'You have received ATHLTH+ for ' || v_days ||
            ' days. Valid until ' ||
            to_char(new.expires_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') ||
            ' UTC.';
    end if;

    insert into public.social_inbox_events
        (recipient_id, actor_id, kind, title, message, entity_type, entity_id)
    values (
        new.user_id,
        null,
        'athlth_plus_granted',
        'ATHLTH+ granted',
        v_message,
        'athlth_plus_grant',
        new.user_id
    );

    return new;
end;
$body$;

revoke all on function private.athlth_notify_plus_grant_recipient()
    from public, anon, authenticated;

drop trigger if exists athlth_plus_grant_recipient_notification
    on public.athlth_admin_plus_grants;

create trigger athlth_plus_grant_recipient_notification
    after insert or update on public.athlth_admin_plus_grants
    for each row execute function private.athlth_notify_plus_grant_recipient();

comment on function private.athlth_notify_plus_grant_recipient() is
    'Inserts a single recipient-scoped ATHLTH+ grant notification in the same transaction as a valid admin grant; existing social inbox trigger queues APNs.';
