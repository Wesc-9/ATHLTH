# ATHLTH 1.7.0 — Supabase security triage (9 October 2026)

Scope: live Supabase project schema checks and the `release/v1.7.0` codebase. This is a technical review, **not** a penetration test or GDPR certification.

## Verified

- 39 `SECURITY DEFINER` functions are present in the exposed `public` schema.
- **Zero** of the 39 are executable by the `anon` role.
- 33 are executable by `authenticated` and trigger Supabase's informational/warning lint. This is not synonymous with 33 confirmed vulnerabilities; the client legitimately calls a number of these functions.
- Inspected functions check `auth.uid()`, ownership or group membership; a few documented exceptions have separate guards:
  - `ensure_official_weekly_challenge_horizon` extends a globally bounded challenge calendar; the app intentionally calls this.
  - `shift_official_weekly_challenges_forward` checks `private.is_app_admin()`.
  - `respond_to_direct_message_request` delegates to the private implementation (its authorization checks still need dedicated regression coverage).
- Neither `anon` nor `authenticated` can create objects in the `public` schema.
- The two RLS/no-policy lint findings, `private.ai_request_budgets` and `public.public_media_moderation_events`, are deliberately closed to direct ordinary-client table access. They are verified to have RLS enabled.
- A new CI test at `supabase/tests/security_definer_rpc_access.sql` guards these access assumptions.

## Remaining work / release gates

1. **Leaked-password protection**: Supabase Auth advises enabling its Have I Been Pwned check. This requires a Supabase Auth project-setting change (not provided by the connected API tools). Review production sign-in method compatibility and enable it in the dashboard; re-run security advisors.
2. **pg_net in public**: the installed `pg_net` version 0.20.4 has `extrelocatable=false`; do **not** attempt a routine schema relocation. Plan any extension recreation with a database backup, an outage window, and inventory of triggers/webhooks depending on `net.*`.
3. **RPC authorization**: add actor/owner/member negative tests for each business-sensitive `SECURITY DEFINER` endpoint; avoid mass revocation of `authenticated` which would break existing clients.
4. **Workout leaderboard integrity**: `record_community_group_workout` records the signed-in account's submitted workout UUID and completion time without independent HealthKit proof. It does **not** confer another account's identity, but can be abused to inflate workout counts. Design a server-verified or clearly marked self-reported provenance model before using club points as fraud-resistant competition scores.
5. **Continuous verification**: release only after backend regression and iPhone/iPad builds pass, and review privacy-provider contracts separately.

## Helpful Supabase references

- https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
- https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public
