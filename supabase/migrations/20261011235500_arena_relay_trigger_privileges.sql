-- Relay planning trigger is not a public RPC. PostgreSQL runs it
-- through the roster-change trigger; clients must use the validated
-- public.arena_save_relay_lineup RPC instead.
revoke all on function private.arena_clear_relay_on_roster_change()
  from public, anon, authenticated;
