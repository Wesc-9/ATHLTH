-- Postgres default privileges may grant UPDATE to authenticated even after
-- revoking PUBLIC. Completed workout sync is append-only: deny all writes
-- except owner-checked INSERT.
revoke update, delete, truncate, references, trigger
  on public.account_strength_workout_sync from authenticated;
revoke all on public.account_strength_workout_sync from anon;
grant select, insert on public.account_strength_workout_sync to authenticated;
