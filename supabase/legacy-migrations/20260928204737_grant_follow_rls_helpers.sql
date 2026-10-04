-- These private helpers are invoked transitively by RLS policies.
-- Grant EXECUTE to authenticated while keeping the private schema unexposed.
grant execute on function private.is_following(uuid)
to authenticated;
grant execute on function private.are_friends(uuid)
to authenticated;
