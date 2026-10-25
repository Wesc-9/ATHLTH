# ATHLTH 1.9.3 — Train implementation and design review

Local branch: `release/v1.9.3`, based on `origin/release/v1.9.2` at `b2b77a02`.
Marketing version 1.9.3, next build 101. No push, TestFlight, production changes,
data migration or changes to previous release branches are part of this work.

## Visual contract

The product surface is the existing iOS Train tab, not a separate preview.
The athlete should find the current workout first, plan a complete week without
losing context, and inspect recorded progress with clear source boundaries.

- Warm ivory canvas, light paper, charcoal ink, bronze text and restrained gold
  structural details. Gold decoration is not used as low-contrast body text.
- One ATHLTH masthead and named Today / Plan / Progress navigation on all three
  screens. No icon-only navigation mode after switching sections.
- Scalable serif display typography, semantic body text, generous section
  spacing, fine rules, asymmetric phase spines and restrained surface depth.
- Today prioritizes the live recorder or planned prescription. Other daily
  sessions remain reachable; discovery and Ghost remain under an explicit
  disclosure. Quick Train retains the existing setup callbacks.
- The active-session surface uses the same paper and typography, a prominent
  live timer and a full-width resume action. The existing elapsed-time source,
  rest countdown and recorder continuation callback remain unchanged.
- Plan uses a charcoal program folio with actual completion, followed by
  full-width day agendas. Selected-day editing opens immediately below its
  day. Every day's sessions are visible, not only its first session.
- The production Plan entry is `planContent -> studioPlanWorkspace`.
  Its `studioPlanCover` and `studioDayRow` now reuse the redesigned header
  and agenda components. The older `premiumPlanDashboard` is not the entry
  point and must not be used alone to assess design coverage. The actual
  empty-plan state, draft recovery and management disclosure are also updated.
- Progress uses a numerical editorial overview, understated category rules,
  adaptive metric layouts and the existing recorded-data charts. The former
  decorative photo/ring hero is removed. Running chart lines do not overshoot
  recorded points through spline interpolation.
- Shared surfaces, navigation, primary buttons, section headings, activity
  tiles, phase rows and metric tiles live in `ATHLTHTrainDesign.swift`.
- Navigation and button motion respect Reduce Motion. Existing animations in
  the three Train surfaces now also respect that preference.
- Progress includes the shared masthead in its scroll content so large text
  cannot reserve the entire analysis viewport. Workout actions use a named
  accessibility label and a 48-point target.

Target widths: 320, 390 and 768 points. Include normal text and Accessibility 3
Dynamic Type. Screenshots and physical-device review are still required.

## Functional changes

### Simple and advanced planning follow-up

- Simple setup remains activity, weekly frequency and session length. An
  optional date/length disclosure now allows 1–52 weeks and a chosen start
  date. Neither changing activity nor creating the plan resets this to eight
  weeks. Existing draft fields retain these choices without a schema change.
- Mode selection describes desired guidance/detail, not age or gender. This
  change does not claim automatic training prescription based on demographics.
- The actual detailed editor is `WorkoutTemplateBuilderView` in
  `WorkoutTemplateCatalog.swift`. Interval groups now offer **Customize each
  effort and recovery**. This materializes the existing execution sequence as
  independently editable saved blocks, preserving order and targets and
  omitting the final between-round recovery exactly as the engine already does.
  Other groups stay intact. Expansion beyond the 200-block plan limit is
  rejected, never truncated. This applies only to the draft until it is saved.
- The running-specific interval composer retains second-level durations when
  editing blocks (45 seconds no longer becomes 60), supports time/distance/open
  recoveries and blocks session saving while its block editor is still open.
  Each repetition continues to support independent work and recovery targets.
- Pace controls support one-second adjustments and a wider manually selected
  range. Pace/speed switching converts the current value. Imported pace ranges
  and RPE survive changes to other fields; explicit pace replacement/removal
  still takes effect. These are athlete-entered targets, never measured data.
- Target and interval-editing XCTest cases cover unchanged execution after
  expansion, changing only effort/pause 3, JSON round trips, preserved targets,
  output limits and Watch transfer. Simple draft coverage checks custom dates
  and length. These tests are **added, not executed on Windows**.

`swiftui-pro` 2.0.0 is installed at `.agents/skills/swiftui-pro`; its data-flow,
view and hygiene guidance is being used alongside ECC. Existing deployment
targets and integration stores remain unchanged. No Xcode MCP tools are
available in this session.

- Shared prescription summary in Today, weekly agendas and selected-session
  details: activity, duration provenance, distance target, group rounds and
  training place. Structured duration is recalculated from the saved recipe;
  an incomplete prescription is not displayed with a stale duration.
- Timeline overview groups adjacent phases without sorting inline recovery or
  repeated phases out of chronological order. It never changes execution data.
- Copy one selected workout to one or several dates, including the same day,
  through the existing version-checked copy API. Copying whole days remains.
  Both the workout menu and its Copy footer select that workout; Copy day
  remains an explicitly named menu action.
- Named Train destinations replace integer tab selectors while retaining all
  existing deep-link and launch call sites.
- General progress includes completed local iPhone recordings before Health
  import. An explicit identity index prefers Health records and avoids counting
  linked local phone/strength records twice, including before Health import.
- Running charts, running records, calories and distance retain their existing
  Apple Health data source. Strength loads retain their manual-entry origin.
  The UI explains those boundaries instead of treating local estimates as
  sensor measurements.
- History refresh responds to account and Health workout changes. Cancelled,
  superseded and previous-account responses are rejected. Partial history
  failures offer pull-to-refresh and do not erase stored history.
- Loading history shows a placeholder instead of a misleading zero in the
  overview metrics. Partial-history warnings precede the affected statistics.
- General progress links to existing goals and trophies. It shows completed
  milestones in the selected period with their stored manual/Health/ATHLTH
  provenance, and clearly labels earned achievements as all-time. Legacy
  milestones without a source are labelled as such. No awards are fabricated.
- Health metrics and record summaries adapt their columns to text size;
  running history and record sections use the full width. Readiness is
  explicitly described as estimated. History rows use scalable text.
- Personal records explicitly describe their all-time scope, independently
  of the selected period for workout history and charts.

## Preserved integrations and limits

No persisted workout schema, HealthKit session lifecycle, Watch transfer model,
completion journal, exercise database or production backend is replaced.
Existing planners, drafts, places, library save, run/strength recording,
interruption recovery and completion flows remain the integration boundaries.

The 1.9.2 hybrid restrictions remain: the safe bridge requires an explicit
indoor/treadmill prescription and rejects outdoor route hybrids. A pure router
is not a complete outdoor multi-activity capture engine. Full outdoor hybrid
capture is **not implemented or claimed** by this redesign.

Identity deduplication relies on explicit links. If historical records have
neither an originating identity nor a Health UUID link, timestamps alone are
not used to discard potentially distinct workouts.

## Verification

Executed on Windows:

- `node --check scripts/verify_train_design.mjs`
- `node scripts/verify_train_design.mjs`: token contrast checks against light
  backgrounds and dark action surfaces. The minimum light-surface text contrast
  is 4.68:1; bronze on paper is 7.20:1.
- `git diff --check`: whitespace/error checks on tracked changes.

Added XCTest coverage (not executed here):

- `ATHLTHRecordedWorkoutIndexTests`: delayed Health import, shared identities,
  repeated delivery and preservation of unlinked records.
- `ATHLTHPlannedWorkoutPresentationTests`: legacy prescriptions, unknown
  structured duration and interval expansion without mutation.
- `ATHLTHWorkoutTimelineOverviewTests`: inline recovery, repeated phases and
  distinct preview identities for repeated legacy blocks.
- `ATHLTHTrainDesignLayoutTests`: actual shared SwiftUI components at the
  target widths and Dynamic Type sizes.
- Additional Plan Studio integration case: single-workout same-day copying
  retains existing sessions, generates a new ID and rejects a stale version.

The existing build and Train/hybrid regression workflows now include 1.9.3 and
the new tests. They have **not been dispatched**. No CI success is claimed.

Required macOS / Xcode verification:

1. Generate the full project with the existing XcodeGen/asset preparation flow.
2. Run Swift syntax preflight, iOS build and the Train/hybrid XCTest workflow.
3. Build the real Watch target; do not treat the iPhone-only test configuration
   as proof that Watch compiles.
4. Render Today (empty, scheduled, multiple, active, completed), Plan (draft,
   selected day, copied/moved workout, stale edit) and Progress (loading, empty,
   populated, partial/error, unavailable Health data) at the target widths.
   Enter Plan through the actual Train tab and verify that its Studio cover
   uses the charcoal folio and that all sessions appear in the daily agenda.
   Verify milestone links, unknown/manual provenance and the trophy collection.
5. Verify VoiceOver, Dynamic Type, Reduce Motion, keyboard/focus where relevant,
   readable charts and bottom-tab clearance. Layout-size tests do not establish
   absence of clipping or correct VoiceOver reading order.
6. On physical iPhone/Watch: start, pause/resume, disconnect/reconnect, reorder
   or append live exercises, terminate/recover and finish/partially finish.
   Verify one saved activity and preserved plan identity in existing supported
   hybrid flows.

`TRAIN_1_9_3_DESIGN_EVIDENCE.json` deliberately records rendering as untested.
The ECC rendered-evidence gate must remain failing until real artifacts and
observations exist. Source review and color arithmetic cannot pass that gate.

## Review boundary

### Coverage of the original request

| Area | Current source status | Remaining verification |
| --- | --- | --- |
| Today and Quick Train | Redesigned actual screen, active/empty/completed states, shared session summary; existing launch callbacks retained | Render all states; start and resume on phone and Watch |
| Plan overview | Actual Studio entry now uses shared program header and full-width multi-session agenda; selected-day editing stays inline | Render actual Train entry, select days and weeks, verify compact/large text |
| Plan creation and editing | Actual `TrainingPlanBuilderFlow` and Train week/workout/block editors use shared styling; simple date/duration controls and individual interval editing added; existing persistence retained | Exercise creation/edit/delete/move/copy, saved places, library and interrupted drafts |
| Progress | Redesigned overview/charts/history; explicit source and time scope; existing milestone and trophy stores connected | Validate populated/empty/partial/account-switch states and destination links |
| Combined workouts | Existing timed indoor hybrid bridge and active exercise queue retained | Real iPhone/Watch continuity and one completion record; outdoor route hybrids remain unsupported |
| Data compatibility | No persisted schema or recording lifecycle changes; identity-based read deduplication added | Run added and existing XCTest regressions; inspect delayed Health sync on device |
| Release readiness | Windows source/contrast checks only; tests and CI configuration prepared | macOS compile, XCTest, rendered review and physical Watch testing remain outstanding |

Planning editor follow-up also updates the week/workout/block headings,
surfaces and save actions, periodization layout, and interval/planner palettes.
Week navigation has named 48-point targets; week selection and interval
transitions respect Reduce Motion. Destination screens outside these flows
have not all been visually rebuilt.

Workout drafts now observe the complete session value rather than a subset
of fields, so running prescriptions and existing exercise edits trigger the
existing draft persistence path. Structured duration estimates also project
running templates and their individual recoveries, avoiding stale legacy
duration values. Unbounded prescriptions explicitly distinguish a manually
allocated planning budget from a complete estimate. Added presentation tests
cover individual recoveries and unbounded running recovery; these tests still
require execution on macOS.
Source presence is not proof of successful end-to-end execution.

This is implemented SwiftUI source with Windows-level verification, not an
approved visual release or a verified replacement workout engine. Changes are
local and uncommitted so they can be reviewed independently before publishing.
