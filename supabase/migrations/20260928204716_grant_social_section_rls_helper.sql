-- RLS policies execute this helper as the authenticated role.
-- The private schema is not exposed through the Data API.
grant execute on function private.can_view_social_section(uuid, text)
to authenticated;
