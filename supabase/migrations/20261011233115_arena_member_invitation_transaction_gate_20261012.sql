-- Serialize accepted/declined invitation responses with competition start.
-- Protect the total invitee limit even for direct Data API inserts.
create or replace function private.arena_guard_member_invitation_write()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  v_status text;
  v_scope text;
  v_count integer;
begin
  if tg_op = 'INSERT' then
    select s.status,s.scope into v_status,v_scope
    from public.arena_series s where s.id=new.series_id for update;
    if not found or v_status <> 'draft' then
      raise exception 'Invitations are locked after competition start';
    end if;
    select count(*) into v_count from public.arena_series_members m
    where m.series_id=new.series_id;
    if (v_scope='duel' and v_count >= 2)
       or (v_scope<>'duel' and v_count >= 21) then
      raise exception 'Arena participant limit reached';
    end if;
    return new;
  end if;

  -- FK SET NULL and privileged scoring retain their existing paths.
  if old.response='invited'
     and new.user_id is not null
     and new.response is distinct from old.response then
    if new.response not in ('accepted','declined')
       or new.slot_id is distinct from old.slot_id
       or new.series_id is distinct from old.series_id
       or new.user_id is distinct from old.user_id
       or new.points is distinct from old.points
       or new.created_at is distinct from old.created_at
       or new.departed_at is distinct from old.departed_at
       or new.replaced_at is distinct from old.replaced_at then
      raise exception 'Only invitation acceptance or decline is permitted';
    end if;
    select s.status into v_status from public.arena_series s
    where s.id=old.series_id for update;
    if not found or v_status <> 'draft' then
      raise exception 'This competition has already started; invitation response is locked';
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function private.arena_guard_member_invitation_write() from public, anon, authenticated;
drop trigger if exists arena_member_invitation_write_gate on public.arena_series_members;
create trigger arena_member_invitation_write_gate
before insert or update on public.arena_series_members
for each row execute function private.arena_guard_member_invitation_write();
