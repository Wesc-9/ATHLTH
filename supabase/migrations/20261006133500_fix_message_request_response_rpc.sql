-- Restore authenticated access to the private message-request response
-- implementation. The public wrapper intentionally exposes the operation, but
-- it must execute as its owner because authenticated clients do not (and should
-- not) have EXECUTE permission on private implementation functions.

create or replace function public.respond_to_direct_message_request(
  conversation_id uuid,
  accept_request boolean
)
returns void
language sql
security definer
set search_path = pg_catalog
as $function$
  select private.respond_to_direct_message_request_impl(
    conversation_id,
    accept_request
  );
$function$;

revoke all on function public.respond_to_direct_message_request(uuid, boolean)
  from public, anon;

grant execute on function public.respond_to_direct_message_request(uuid, boolean)
  to authenticated;
