-- Restore the intended permission chain for direct-message conversation creation.
-- The public RPC remains the only Data API entry point; the private schema is
-- not exposed through PostgREST. The helper still validates auth.uid(), blocks,
-- mutual-follow state and the recipient's messaging preferences.

revoke execute on function private.get_or_create_direct_conversation_impl(uuid)
from public, anon;

grant execute on function private.get_or_create_direct_conversation_impl(uuid)
to authenticated;
