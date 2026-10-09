-- Defense in depth: these SECURITY DEFINER RPCs are for authenticated
-- community members/organizers only. Earlier migrations left EXECUTE
-- available to PUBLIC / anon when replayed from a fresh database.
-- Their function bodies already check auth.uid() and role/ownership.
-- Preserve intentional authenticated and service-role access.

revoke execute on function public.community_event_set_lifecycle(uuid, text)
  from public, anon;
grant execute on function public.community_event_set_lifecycle(uuid, text)
  to authenticated, service_role;

revoke execute on function public.set_community_group_announcement_pin(uuid, uuid)
  from public, anon;
grant execute on function public.set_community_group_announcement_pin(uuid, uuid)
  to authenticated, service_role;
