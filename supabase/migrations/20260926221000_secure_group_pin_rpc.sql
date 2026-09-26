revoke all on function public.set_community_group_announcement_pin(
  uuid,
  uuid
) from public, anon;

grant execute on function public.set_community_group_announcement_pin(
  uuid,
  uuid
) to authenticated;
