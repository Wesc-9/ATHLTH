create function public.set_workout_room_presence(p_source uuid,p_status text) returns void language sql security invoker set search_path=pg_catalog,public as $$
 insert into public.social_workout_room_presence(source_workout_id,user_id,status) values(p_source,auth.uid(),p_status)
 on conflict(source_workout_id,user_id) do update set status=excluded.status;
$$;
revoke all on function public.set_workout_room_presence(uuid,text) from public,anon;
grant execute on function public.set_workout_room_presence(uuid,text) to authenticated;