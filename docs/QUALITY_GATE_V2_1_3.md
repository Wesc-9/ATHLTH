# ATHLTH 2.1.3 – security, data integrity, performance and device QA

This is a verification gate for the active development branch, **not** an
authorization to upload a TestFlight build. Assess the final *same commit*;
successful results from older commits do not qualify.

## Phase 1 – security and stored workout integrity

- [ ] Same-commit `Build ATHLTH`, backend regressions and applicable iPhone/iPad smoke tests pass.
- [ ] In Supabase, review all **authenticated SECURITY DEFINER RPCs** for
  ownership, membership and actor authorization. Three intentional
  auth.uid()-free wrappers have documented delegated access checks in
  `supabase/tests/security_definer_rpc_access.sql`; verify changes when
  adding or editing functions. Do not bulk-revoke client RPCs.
- [ ] Review the Supabase security advisor: authenticated SECURITY DEFINER
  calls, `pg_net` location, leaked-password protection and RLS rules.
  Resolve according to impact, not advisory count alone.
- [ ] Validate that cloud backup is opt-in; restore cannot replace another
  account's keys and a malformed payload leaves current data untouched.
- [ ] Simulate app termination halfway through cloud restore; on next launch
  `TrainingBackupRestoreJournal` must finish the account-scoped snapshot
  before stores read the restored data.
- [ ] Confirm restoring a backup while already signed in correctly refreshes
  displayed stores. A successful UserDefaults write alone is not proof of
  an updated in-memory training plan.
- [ ] Check delayed Watch completion/strength command delivery after an ATHLTH
  account switch: no imported workout may be attributed to another account;
  never discard unassigned results silently.
- [ ] Verify that an imported external HealthKit workout is approved once,
  deleted Health samples are reconciled, and sync replay adds no duplicates.

## Phase 2 – measurable performance

- [ ] On a physical iPhone, run Xcode Instruments Time Profiler, Hangs,
  Allocations, SwiftUI and signposts. Capture cold launch and warm switches:
  Home → Train → Insights → Explore → Community → Home, repeated 10 times.
- [ ] Inspect `TabHome`, `TabTrain`, `TabInsights`, `TabExplore`,
  `TabCommunity`, `HomeInitialData`, `ExploreTabRefresh`,
  `CommunityTabRefresh`, `InsightsTabRefresh` and
  `HealthHistoricalRead` signposts.
- [ ] Check older HealthKit histories (hundreds/thousands of workouts).
  Multiple simultaneous historical consumers should share the same
  in-flight fetch; verify a new workout invalidates stale aggregate data.
- [ ] Profile route/map annotation count and image decoding with many
  nearby routes, including foreground/background tab switching.
- [ ] Profile Supabase queries for home feed, Arena, clubs, notifications
  and train-together; use `EXPLAIN (ANALYZE, BUFFERS)` on representative
  test data before modifying indexes or RLS predicates.
- [ ] Compare p50/p95 tab latency, main-thread hangs, cold-start time,
  memory peak, and scrolling smoothness to the pre-change baseline.
  Do not publish an invented speedup without device measurements.

## Phase 3 – workout, Watch and connectivity acceptance

- [ ] Start, pause, resume and end each workout type from iPhone and Watch.
- [ ] Lock both screens and background/terminate the iPhone app mid-workout.
  The current session must resume with correct elapsed *active* time.
- [ ] Disconnect Bluetooth, Wi-Fi and cellular independently; reconnect
  without a second HealthKit session or duplicate ATHLTH history entry.
- [ ] Complete a strength workout while Watch is offline; replay commands,
  sets, weights, pet participation and HealthKit summary on reconnect once.
- [ ] Verify Ghost Race start gating, stale-GPS suppression and synchronized
  completion using two real accounts and real devices.
- [ ] Check Watch Always-On and interval haptics without excessive battery use.
- [ ] Test a delayed completed workout result during sign-out/account switch.

## Phase 4 – modular source organization

- [ ] Extract behavior-preserving leaf components from large root views first.
- [ ] Keep shared iPhone/iPad workout editors and plan models; do not fork
  separate tablet business logic.
- [ ] For each extraction, run the same-commit iPhone/iPad build and verify
  sheet dismissal, selected tab, navigation restoration and workout overlay.
- [ ] Do not combine architectural cleanup with new features in the same change.

## Phase 5 – product and accessibility QA

- [ ] iPhone: create/edit/duplicate/delete a running, strength and hybrid plan.
- [ ] iPad: edit the same plan in landscape and narrow Stage Manager windows;
  resize/move focus and return to a draft without losing its state.
- [ ] Verify offline launch, local workout recording, later synchronization,
  cloud-backup opt-in, restore and account separation.
- [ ] Check Norwegian and English text, VoiceOver order, Dynamic Type and
  Reduce Motion on navigation, forms and progress charts.
- [ ] Review GDPR disclosures for third-party Coach processing and category-
  specific approval; no automatic health sharing without release approval.
- [ ] Inspect important empty, error, partial-data and permission-denied states.

## Release gate

- No TestFlight upload unless the owner explicitly requests it.
- A passing compile or backend test is not a substitute for physical Watch
  acceptance, real-device performance measurement, or privacy review.
- Record the final commit, CI run links, device/OS, reproducible test results
  and any remaining exclusions before calling the quality round complete.
