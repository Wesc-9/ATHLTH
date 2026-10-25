# ATHLTH – Train / Treningsplan / Detaljert økt (v1.9.2)

Updated 2026-10-25. This is the approved scope and implementation tracking for the Train detailed plan editor. Work only in release/v1.9.2 until explicitly instructed otherwise. No TestFlight upload without a separate instruction.

## Approved athlete workflow

A single planned session consists of ordered **Oppvarming → Hoveddel → Nedtrapping**, with optional **Pause** blocks between exercises or intervals. Each part may contain any number of exercise, running, walking, cycling, yoga or stretching steps. For example:

- Oppvarming: 10 minutes cycling, planned pulse zone 2, RPE 3/10
- Hoveddel: squat 3×8 with weight/load, 90-second rests; then 4×4 running intervals with planned pace and pulse zone
- Nedtrapping: 5 minutes easy running followed by timed mobility

The plan editor lets the user choose a part and add a typed step directly; not through a separate exercise engine. Each step supports activity-appropriate duration, target heart-rate zone or perceived effort (RPE), plus strength reps/sets/load or running pace/distance. Planned targets are never represented as recorded measurements.

## Implementation progress

- [x] Plan landing page shows actual active plan, week and seven day cards before builder controls
- [x] Recover draft from existing draft store; never overwrite recorded sessions
- [x] Add phase-first controls in WorkoutTemplateBuilderView with running, strength, cycling and more
- [x] Insert new blocks before correct later phase, preserving interval/superset group boundaries
- [x] Timed strength steps; per-step pulse-zone and RPE intensity metadata, historic decode compatibility
- [x] Mixed cycling/strength/run classify as hybrid, while cycling-only/walking-only keep their own categories
- [x] Cycling plan steps route to distinct cycling display inside the single structured live workout
- [x] Regression tests added for phase placement, category, target persistence and engine transition
- [ ] Latest full iOS build and simulator test for release/v1.9.2 is green
- [ ] Manual UI check: small iPhone, large iPhone, accessibility, correct selected phase on exercise-picker dismissal
- [ ] Device QA: resume/recover active mixed workout on iPhone/Watch and verify one workout summary
- [ ] Verify detailed interval goals and the Audio Coach across motor transitions

Important: the current cycling live segment is a *timed display*, not a new sensor capture engine. It must not imply measured cycling cadence, speed, location, watts or independent Watch recording without actual sensor provenance.

Do not mark device/build verification complete until a matching green CI run and relevant device tests exist.
