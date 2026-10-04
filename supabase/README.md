# ATHLTH 1.6.0 database history

`migrations/` contains the 128 applied migrations recovered read-only from
`hnkybbzxffvyhzrstqdo` on 2026-10-04, followed by the new 1.6.0 audit migration.
The recovered filenames use the versions recorded by Supabase. The previous
repository history used different versions, duplicated some timestamps and
omitted foundational migrations. Replaying it could not recreate the database.

`migration-history.json` records hashes of the recovered SQL after normalizing
trailing whitespace. `python3 scripts/verify_v160_contracts.py` checks the
manifest and unique migration versions.

`legacy-migrations/` preserves every previous repository SQL file for comparison.
These are archival source files, **not migrations to apply**. Some represent
changes that were never applied under their repository filenames. Reconcile any
desired differences explicitly in a new migration; do not replay the archive.

Local development uses the checked-in CLI configuration (Postgres 17). Run
`supabase start`, `supabase db reset --local --no-seed`, then
`psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -v ON_ERROR_STOP=1 -f supabase/tests/v160_audit.sql`.
The SQL test creates temporary fixtures inside a rolled-back transaction and
must only run on a disposable local database.

For the existing hosted project, compare `supabase migration list --linked`
before pushing. Only the new audit migration should be pending. Do not repair,
reapply, or reset already-applied migration versions.

See [the audit rollout notes](../docs/v1.6.0-audit-fixes.md) before deployment.
