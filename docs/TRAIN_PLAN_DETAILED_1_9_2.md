# ATHLTH 1.9.2 – Detailed mixed-activity training plan

Status: partially implemented on `release/v1.9.2`. This specification records the user's approved workflow; unchecked items are NOT claims of completed app functionality.

## User-facing flow
- Train → Treningsplan → choose a date/session → detailed workout builder.
- A *single* session is built chronologically in three phases: **Oppvarming**, **Hoveddel**, **Nedtrapping**. **Pause** is an inline step inside the selected phase, not a fourth separate workout.
- Within every phase, append and reorder multiple blocks of any supported kind: running, walking, strength exercises, cycling, yoga, mobility/stretching, rest, intervals, supersets, optional meditation/recovery.
- Each activity has individual planned duration (or distance for running), plus **target intensity**: heart-rate zone 1–5, subjective RPE 1–10; pace for running; sets, reps, load and set rests for strength. Targets are explicitly user-planned and never presented as measured data.
- Show each phase's ordered step names and targets directly in the phase overview. Detailed per-block editing remains in the unified timeline; the saved order determines execution. Grouped interval rounds and pauses must remain together when inserted or moved.
- Time summary uses specified durations, expanding interval rounds and rests. Unknown or distance-based time is *not* invented. The summary should distinguish known duration from estimated duration if a separate estimator is used.
- Existing drafts, day/week copying and `Lagre til mine økter` must remain intact.

## Example (illustrative, internally consistent)
- Oppvarming: 10 min cycling (zone 2), 5 min mobility (RPE 3) = 15 min
- Hoveddel: strength 20 min + four 4-minute runs with three 2-minute rests = 42 min
- Nedtrapping: 5 min walking + 5 min stretching = 10 min
- Specified duration totals 67 min, before any separate transitions/unmeasured delays.

## Architectural and safety constraints
- One authoritatively ordered `workoutBlocks` / `WorkoutTemplateBlock` timeline. A `PlannedSession` holds one set of plan identifiers; do NOT create extra simultaneous HealthKit workouts when changing activity type.
- Reuse `ATHLTHUnifiedWorkout`, `ATHLTHLiveWorkoutEngineRouter`, strength/run planners and existing phone/Watch coordination. The router alone is only a **routing contract**; complete real-time engine handoff is a separate deliverable and is not validated by a builder UI commit.
- Explicit rests and interval groups must inherit the selected phase; preserve grouping on insertion and migration. Legacy `.recovery` steps should remain visible and executable.
- Live activity-specific input: run pace/distance, cycling timer/effort (never pretend to have power/cadence sensors), strength reps/sets/rest; Watch measurements shown only if measured and fresh. No duplicate training records.
- Prevent discarded edits/unfinished workouts due to tab changes; maintain privacy, accessibility, old-plan decoding and draft persistence.

## Implemented on release/v1.9.2 (requires CI verification)
- [x] Phase accordion for warmup / main / cooldown in `WorkoutTemplateBuilderView`
- [x] Insert mixed running/strength/cycling and optional other activities into phase
- [x] Per-step duration and intensity controls; plan targets stored as optional metadata
- [x] Insert independent pauses and new interval groups into the selected phase
- [x] Ordered per-phase step/target summaries
- [x] Regression tests for phase insertion and group integrity

## Remaining verification and delivery
- [ ] A complete **green** iOS build + regression run on current HEAD
- [ ] Device checks: reorder/move mixed blocks, cancel/save/resume drafts, copy dates/weeks, validate intensity/time in active planned session
- [ ] Verify expanded interval duration calculations and edge cases where step length is based only on distance/reps
- [ ] Confirm the live iPhone + Apple Watch engine switch (running↔strength↔cycling) preserves one workout ID, timer, heart-rate source and single saved workout, including recovery and interruption scenarios
- [ ] Final narrow/large iPhone visual QA and VoiceOver labels
- [ ] TestFlight only upon explicit separate user request
