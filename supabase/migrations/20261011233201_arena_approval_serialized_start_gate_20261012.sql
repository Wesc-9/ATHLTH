-- Arena: serialize rule votes with competition start.
create or replace function private.arena_guard_round_approval_before_insert()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, private
as $function$
declare v_status text;
begin
  select s.status into v_status
  from public.arena_series s
  join public.arena_round_proposals r on r.series_id=s.id
  where r.id=new.round_id for update of s;
  if not found or v_status <> 'draft' then
    raise exception 'Round approvals are locked after competition start';
  end if;
  return new;
end;
$function$;
revoke all on function private.arena_guard_round_approval_before_insert() from public, anon, authenticated;
drop trigger if exists arena_approval_start_gate on public.arena_round_approvals;
create trigger arena_approval_start_gate before insert on public.arena_round_approvals
for each row execute function private.arena_guard_round_approval_before_insert();
