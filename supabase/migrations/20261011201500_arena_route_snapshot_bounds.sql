-- Arena route payload hardening. Validate the shape before storing it.
-- Prevent unbounded map polylines or malformed GPS coordinates from clients.
create or replace function private.arena_route_snapshot_valid(
 p_payload jsonb, p_target_meters numeric
) returns boolean
language plpgsql immutable security invoker
set search_path=pg_catalog,public,private
as $$
declare
 v_point jsonb;
 v_lat numeric;
 v_lon numeric;
 v_distance numeric;
begin
 if p_payload is null or jsonb_typeof(p_payload)<>'object' then
   return false;
 end if;
 if jsonb_typeof(p_payload->'coordinates')<>'array' then
   return false;
 end if;
 if jsonb_array_length(p_payload->'coordinates') not between 2 and 1500 then
   return false;
 end if;
 if jsonb_typeof(p_payload->'distanceKilometers')<>'number'
   or p_target_meters is null or p_target_meters not between 100 and 500000
   or length(btrim(coalesce(p_payload->>'title',''))) not between 1 and 200
   then return false;
 end if;
 v_distance := (p_payload->>'distanceKilometers')::numeric * 1000;
 if abs(v_distance-p_target_meters) > greatest(5,p_target_meters*0.001) then
   return false;
 end if;
 for v_point in select value from jsonb_array_elements(p_payload->'coordinates') loop
   if jsonb_typeof(v_point)<>'object'
     or jsonb_typeof(v_point->'latitude')<>'number'
     or jsonb_typeof(v_point->'longitude')<>'number' then
     return false;
   end if;
   v_lat := (v_point->>'latitude')::numeric;
   v_lon := (v_point->>'longitude')::numeric;
   if v_lat not between -90 and 90 or v_lon not between -180 and 180 then
     return false;
   end if;
 end loop;
 return true;
exception when invalid_text_representation or numeric_value_out_of_range then
 return false;
end;
$$;

revoke all on function private.arena_route_snapshot_valid(jsonb,numeric)
  from public,anon;
grant execute on function private.arena_route_snapshot_valid(jsonb,numeric)
  to authenticated;

alter table public.arena_round_proposals
  drop constraint if exists arena_route_payload_bounds_check;
alter table public.arena_round_proposals
  add constraint arena_route_payload_bounds_check
  check (
    template <> 'fastestRoute' or
    private.arena_route_snapshot_valid(route_snapshot,target_distance_meters)
  );
