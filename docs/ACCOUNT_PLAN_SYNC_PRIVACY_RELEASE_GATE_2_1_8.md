# ATHLTH 2.1.8 — account-owned training plan sync: privacy and safety release gate

Status: CODE STAGED, NOT APPROVED FOR DEPLOYMENT. This is an engineering assessment, not legal sign-off.

## Product contract
- Signed-in iPhone and iPad use the same private user account for plan documents. No separate optional plan-sync toggle for new accounts.
- Plan edits first persist locally for offline use, then synchronize when authenticated and online.
- Keep compare-and-set revision checks, remote/local fingerprints, conflict review, and account ID checks. Never use last-writer-wins.
- Legacy users who explicitly disabled cloud plan synchronization remain opted out until they choose to re-enable account synchronization. Never silently reinstate deleted cloud copies.
- Sync status and conflicts remain visible in Account settings. Remove the separate opt-in/out control, not troubleshooting or privacy rights.
- Plan-only synchronization must not silently expand into raw HealthKit samples, workout history, heart-rate streams, GPS traces, Coach interactions, or social content.

## GDPR and platform review before shipping
1. Document whether account plan storage is strictly necessary to provide the signed-in cross-device plan service under GDPR Art. 6(1)(b). A contract is not sufficient for optional secondary purposes.
2. Audit every property of encoded TrainingPlan, including free-text notes, goals, limitations, injuries, personal performance and planned locations. These may disclose health or other sensitive information. Identify and document an Art. 9 exception (commonly explicit consent if appropriate); otherwise exclude sensitive fields from account sync. Do not assume Art. 6(1)(b) alone suffices for health data.
3. Publish clear, versioned onboarding and privacy notices before first account cloud upload: scope, purposes, retention, processors, transfers, access, export, erasure, and consequences of deletion. Do not fabricate retroactive consent.
4. Check whether DPIA is required for health and location profiling, especially AI-powered plan adaptation. Review data processing agreements, subprocessors, transfer safeguards, and account deletion cascade.
5. Confirm Supabase table RLS using auth.uid() for SELECT/INSERT/UPDATE/DELETE, RPC uses invoker permissions, no service-role key on client, and legacy opt-out is server enforced.
6. Account deletion and export must include plans, retained server copies, and compatible backup flows. Define purge/retention periods and deletion propagation to offline devices before GA.
7. Review Apple HealthKit rules and App Store privacy disclosures for actual transferred categories. The sync feature itself must never upload raw HealthKit records.
8. Verify local-at-rest protection, TLS in transit, account switching and sign-out clearing, authentication refresh, and non-identifying logs.

## 2026-11-11 implementation review
- Live Supabase inspection: 0 cloud plan documents, 0 recorded plan-sync opt-ins and 0 opt-outs at inspection time; deployed RLS STILL requires the older consent record. The account-owned migration is staged in GitHub only, NOT applied to production.
- The Swift plan-sync upload gateway now blocks plans with populated `builderProfile.injuriesOrLimitations`; this covers normal uploads and manual conflict resolution. The device retains the unmodified plan.
- WARNING: this is a narrow safety gate, not a complete free-text or special-category data scrubber. `TrainingPlan.summary`, `builderProfile.goalDetail`, block goal text, workout/exercise/set notes and descriptive titles may still contain medical or sensitive data. Do not release default account uploads until those fields are classified and safe processing has been implemented and reviewed.
- Added tests for the injury-field gate and staging RLS account isolation. They have not been executed as end-to-end device tests. Test runner must use a disposable account and rollback.
- The source control work does not prove cross-device sync or GDPR compliance. Running an iOS/iPadOS build and staging database tests remains mandatory.

## Device-private note projection (2026-11-11)
- Account sync now serializes `ATHLTHStudioPlanSyncStore.accountCopy(of:)` rather than the full `TrainingPlan`. It excludes the plan summary, explicit injury/limitation entry, goal detail, block goal prose, session notes, strength exercise and set notes, workout meeting points and training-place metadata. Local source plans are not mutated.
- On downloading a matching plan to the same authenticated owner, `restoringDeviceOnlyFields` restores those device-private fields from that device's existing plan. Other devices never receive the excluded text, even if it describes injuries. If a new device has no local copy, excluded notes are intentionally unavailable.
- Account fingerprints exclude device-only notes and ignore local version/timestamp changes, while retaining the compare-and-set server revision and actual account-plan content.
- Important limitation: user-supplied titles, exercise instructions, nested workout block data, external references and other descriptive fields could still include health or location details. The projection is **not** a comprehensive de-identification or GDPR Art. 9 solution; require payload inspection and privacy review before enabling production account-sync rollout.
- Source-level test assertions were added for the projection and restoration. Full Swift/Xcode build and live cross-device tests still need execution.

## Additional nested-payload audit (2026-11-11)
- The account projection now removes stored recovery-before/recovery-after exercise snapshots and original daily-alternative workout snapshots, since these can retain private notes outside the active exercise list.
- It also removes free-text notes in structured workout blocks and restores those local notes to matching workout/block identities after remote plan import.
- Tests cover exclusion/restoration in Basic and Advanced. This change has not undergone an Xcode build; run the test target before enabling account sync in production.
- Do not deploy the staged DB migration to production until end-to-end tests and disclosure review pass. No production data or RLS policies were changed in this phase.

## Required test matrix
- New signed-in account, iPhone -> iPad -> iPhone edits, plus fresh reinstall.
- Offline edits and reconnect; conflict after both devices edit, including deletion and stale revision.
- Users with historical explicit opt-out (local and server false): no upload or download before choice.
- Legacy opt-out upgrade after visible explanation: account sync starts safely.
- Another account on shared device: no cross-account import, caches or status leakage.
- Signed-out and expired auth: no cloud access, local plan remains safely scoped.
- RLS: user A cannot read/write/delete user B; anonymous cannot access documents; stored RPC respects opt-out.
- Privacy: no HealthKit samples, heart rates or GPS traces in plan payload; inspect any free text for health disclosures.
- Account export and erasure, including cloud and retained backup procedures.
- iOS and iPadOS build and UI tests; Supabase migration must be deployed before enabling new account-based client behavior.

## Deployment sequencing
1. Legal/privacy data classification and notice approval.
2. Supabase migration to staging; RLS/security tests and backups.
3. Client update to TestFlight; check legacy migration and two-device tests.
4. Roll out with monitoring for conflicts and failed syncs, no private notes in telemetry.
5. Production migration only after the preceding gates pass.

Sources: GDPR Arts. 5, 6, 9, 25, 28, 32, 35; Datatilsynet guidance on lawful basis and privacy by default; Supabase RLS/security documentation.
