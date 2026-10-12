# ATHLTH 1.7.3 — Live Workout implementation roadmap

Baseline: `release/v1.7.3`. Keep recording engines, workout ownership, iPhone/Watch sync and HealthKit continuity unchanged. Make small, reversible, direct commits. Do not deploy to TestFlight unless requested.

## Phases and acceptance criteria

1. **Shared live presentation policy (in progress)** — Shared, testable hierarchy for workout phase, primary/secondary metrics, and context-dependent watch pages. AOD can consume it without touching workout recording.
2. **Apple Watch strength (in progress)** — Distinct active-set, countdown, rest, exercise-queue and status pages; Crown input and explicit set completion; preserve warm-up, zero weight, resistance-level and RPE/RIR rules.
3. **Apple Watch running** — Readable pace/distance, structured interval, pulse/zone, route, Ghost/Arena, Audio Coach and controls; only relevant pages shown; no surprise auto-swipes.
4. **Always-On (in progress)** — Single low-power, read-only presentation selected by activity and phase, including accurate rest countdown. No animations, sensitive details policy, stale-data treatment and small-screen testing.
5. **iPhone live workout (in progress)** — Activity-first hero metric and details, aligned with Watch; strength, run, treadmill, intervals and companion mode.
6. **Lock Screen / Dynamic Island (in progress)** — Use existing Live Activity infrastructure and phase-specific compact/expanded variants; terminate cleanly when workout ends.
7. **Other workout modes (in progress)** — Walking, HIIT, cycling, functional, rowing, stairs, yoga; never show irrelevant or unmeasured metrics.
8. **Personalization and accessibility** — Primary metric, preferred pages, strong contrast, readable long exercise names, haptics and AOD privacy.
9. **Regression and device validation** — HealthKit starts/stops, offline Watch operation, reconnect, no duplicated sets/workouts, battery tests, size classes, Always-On and TestFlight manual review.

## Implementation principles

- One underlying workout and one authoritative state. Display models are derived, not separately persisted as a second source of truth.
- A duration *target* is not an active countdown. Mark it as a target until the engine supplies a running timer.
- A resting state must not auto-complete a set; expired rest can announce readiness.
- A missing or stale sensor value must never be presented as fresh.
- AOD is read-only; controls remain on the interactive watch pages.
- Preserve existing route guidance, Ghost/Arena, Audio Coach and Train Together.
- Each phase requires relevant unit checks and build validation before being marked complete.

## Step 2 — delivered in this increment

- New interactive Watch page structure: set / rest, workout status, exercise queue,
  heart-rate detail, music and controls, with the existing Digital Crown editor preserved.
- Read-only Watch page for strength workouts configured for iPhone-only input,
  to avoid displaying actions the paired device will reject.
- A new rest period brings the Watch back to the set/rest page; expiry displays
  READY and requires a deliberate tap. No automatic skip-rest on the Watch UI.
- The set screen now distinguishes warm-up from working sets and shows heart rate.
- Time-based strength targets are explicitly marked as targets, not falsely
  represented as an active timer.
- Remaining follow-up before Step 2 is fully complete: transport of *active*
  time-set countdown state, Watch controls and offline reconciliation. Do not
  claim bidirectional timed-set support until those are implemented and tested.
- Physical Apple Watch layout testing and Xcode/watchOS build remain release gates.

## Step 2 — timed strength countdown integration

- Optional date-anchored `WatchTimedStrengthCountdown` within the existing
  backwards-compatible strength snapshot; no secondary workout/session started.
- iPhone's authoritative `StrengthTimedSetCountdown` is exposed to Watch
  through `watchSnapshot`, updated whenever the countdown is changed.
- Three set-scoped Watch commands: start/resume, pause and reset. They use
  existing durable Watch command transport and exercise/set identity guards.
- Optimistic local Watch countdown state avoids round-trip delay; subsequent
  iPhone snapshots reconcile it. Completing the set clears the local timer.
- Dedicated first Watch page for timed sets; existing Crown editor remains
  available via the next page. AOD shows remaining/paused/ready state using
  the same absolute-date anchor.
- Timed sets still require an explicit completion action: no automatic
  recording when the countdown expires.
- Validation gate: compile both targets and regression tests, then check
  offline/reconnect and device behavior before TestFlight.

## Step 3 — incremental Watch run pages

- Preserve the existing primary metrics, structured step, treadmill incline,
  route navigation, live Ghost/Arena, Spotify and workout-control pages.
- Add a dedicated pulse screen with current, average and maximum values,
  plus the configured heart-rate target when available.
- Add a first-class Audio Coach screen when configured, using existing
  enable/mute/status/replay actions without changing the coach engine.
- Follow the shared presentation policy on the live hero: pace before distance
  when running; distance before pace when walking.
- No new HealthKit session, no new WatchConnectivity ownership and no
  automatic changes to active workout phase or user-selected page.
- Next acceptance gate: successful iOS and watchOS compilation, followed
  by Watch screen-size and wrist-down tests.

## Step 3 — interval, zone and Ghost/Arena focus

- Structured running step gets a dedicated performance page showing step
  name, remaining time/distance, progress, pace target, step time/distance and
  next interval. Remaining value is resolved from existing Watch workout
  elapsed time/distance, not a separately scheduled timer.
- Open-ended intervals show an explicit untimed state, never a fabricated
  countdown. Missing or invalid targets stay unavailable.
- Watch pulse target screen shows below/within/above target only when the
  range and measured heart rate are usable.
- A separate Ghost/Arena page shows opponent identity, validated gap and
  optionally verified progress. Paused, stale or unverified Ghost telemetry
  cannot display the last known distance as a current lead.
- Main metrics page preserves the current structured running step label even
  when a Ghost/Arena opponent is connected.
- Preserve navigation, Spotify, treadmill incline, audio coach and existing
  HealthKit/route/Ghost engines.
- Review actual watchOS/iPhone compilation and device-size layouts before
  treating step 3 as completed.


## Step 4 — contextual Always-On implementation

- One low-power, read-only Watch dashboard. Workout, HealthKit and
  WatchConnectivity ownership are unchanged.
- Shared, testable resolver chooses current-set reps, completed-exercise
  status, strength rest, strength timed countdown, structured running
  interval (time/distance/open), run pace/distance, walk distance/pace or
  elapsed time for other activities.
- Strength rest and timed sets derive remaining seconds from absolute
  reference dates; never automatically advance sets or start a second timer.
- Structured running interval reads current step progress from the existing
  Watch workout engine; open steps never receive a fabricated countdown.
- The low-luminance surface retains pace/distance and workout elapsed time
  where relevant. Ghost only displays a verified, recent gap outside of
  structured-interval priority.
- The footer shows only fresh heart rate, with a small zone marker when a
  valid current sensor sample and configured zone are available.
- No maps, photos, gradients, rapid animations, sound, touch controls or
  persistent additional workout-session work in the Always-On view.
- Final release gate: successful Watch/iOS build, simulator screens for
  small/large watches, physical wrist-down power/refresh checks and
  Watch/phone offline continuity. Do not call battery performance
  validated without physical measurement.


## Step 5 — iPhone hierarchy and mirrored strength (increment 1)

- Mirror mode: run pace is the primary hero measurement; walking uses
  distance. Current step name/progress remain close to the hero.
- Mirrored Watch time, distance/pace, pulse and optional treadmill incline
  are secondary cards, not oversized headline figures.
- Watch sample timestamps gate live heart rate and current pace on the phone.
  If live pace is unavailable, an appropriately labelled measured average is
  used only when the workout has recorded distance/time.
- Mirrored strength gets a noninteractive current exercise panel with set,
  reps/weight or rest-ready countdown. Only the Watch/strength engine owns
  recording and completion.
- Phone-owned running panel promotes pace, retains distance/time as secondary
  metrics, and presents treadmill incline as contextual information.
- Small, reversible presentation-only changes; HealthKit, GPS, sets,
  Ghost, navigation, audio and workout controls remain owned by their
  existing stores. No TestFlight deployment requested.
- Remaining before completion: focused iPhone strength layout physical QA,
  shared interval phase consistency, iPad sizing, and compile/test gates.

## Step 5 — focused strength, responsive phone and data freshness (increment 2)

- Focused strength status now displays workout duration, completed/total
  sets, a compact progress bar and a phase indicator: working set, timed-set
  target/running/paused/completed, planned/rest-ready, exercise complete
  and workout complete. This is presentation-only; it cannot skip rest or
  complete a set.
- Main focused strength content is centered with a sensible width limit on
  iPad; primary exercise cards, Crown/Watch input, set logging and timers
  retain their existing functions. Phone-owned running metrics are likewise
  width-limited for large displays.
- Mirrored iPhone workout elapsed time extrapolates only from fresh Watch
  snapshots. After the freshness window the last measured elapsed value is
  held and a delayed-data indicator is shown for both run and strength.
  Recording continues on Watch independently; reconnect reconciles display.
- Unit tests cover strength phases, expired rest without automatic
  advancement, stale/future Watch packets, mirrored running/paused clocks.
- Remaining device gate: real Watch/iPhone reconnect, iPad/small iPhone
  screen-size checks, a complete Xcode build, and TestFlight review on request.


## Step 6 — Lock Screen and Dynamic Island (increment 1)

- A shared pure display policy chooses paused, strength rest, timed strength
  set, reps, running interval, run pace, walk distance and generic elapsed.
- Optional (backwards-compatible) snapshot fields carry the actual remaining
  interval time/distance and timed-strength-set date anchor from the existing
  workout engines. No new recording session or duplicate countdown.
- The Widget extension links the shared policy explicitly in project.yml.
- Compact and expanded Dynamic Island, and the Lock Screen activity, now
  render the activity/phase headline before supplemental route, target,
  Ghost and sharing details. Off-route warning icon stays prominent.
- Paused workout time uses recorded active elapsed time: do not show a
  continuous clock from workout start that includes paused minutes.
- Timed set and strength rest show READY at zero without automatically
  completing a set. Live Activity remains read-only.
- Delayed widget snapshots suppress stale supplemental race/location
  readings. When updates pause, display a delayed-data indicator rather
  than silently showing an old verified Ghost gap as live.
- Lifecycle remains with ATHLTHSurfaceCoordinator: updated by existing
  Live Activity sync, ends on completed/failed/absent workout, respects
  Dynamic Island enabled/disabled setting.
- Device acceptance gate remains open: compile widget/app/Watch targets,
  verify Lock Screen and each Dynamic Island size on real iPhones, pause,
  resume, reconnect and battery/power behavior. Do not upload to TestFlight
  unless explicitly requested.

## Phase 6 — session-lifecycle safety

- A dedicated session identity (activity icon and workout start, with a
  conservative fallback for legacy nil start dates) prevents the next workout
  from reusing the previous Live Activity.
- Reuse only an activity with matching identity. Obsolete activities are ended
  immediately; duplicate activities for the same workout are collapsed.
- Completed/failed snapshots may only finish activities belonging to their
  original workout; a delayed completion cannot close a newer session.
- A revision check stops an older in-flight update from publishing after a
  newer update replaced it. Temporary Watch disconnection leaves the
  recording workout alone, and the user-facing surfaces mark stale data.
- Final release testing still requires iOS simulator compilation plus real
  disconnect/reconnect, quick back-to-back starts and Live Activity dismissal.

## Phase 7 — measured, activity-specific Watch and iPhone displays

- Cycling: distance becomes the headline only when a finite, positive
  recorded distance exists. Otherwise elapsed time remains the primary.
- Walking/running retain their pace/distance hierarchy from phase 3–5.
- HIIT, functional, rowing, stairs, yoga and other workouts prioritize
  elapsed time, with fresh pulse/recorded calories as secondary values.
  No fabricated strokes, flights, speed, repetitions or route distances.
- Watch wrist-down cycling gets a low-power measured-distance variant.
  iPhone mirrored cycling gets a matching activity-first panel.
- Presentation-only changes: existing HealthKit session, mirroring,
  pause/end commands and sensors are untouched.
- Physical layout, Xcode/watchOS and battery validations remain pending.


## Phase 7 — dedicated other-sport pages (increment 2)

- Non-running/strength Apple Watch workouts now open a dedicated,
  activity-labelled focus page (HIIT, functional, rowing, stairs, yoga,
  cycling, other), with a large recorded workout time or verified cycling
  distance, plus fresh pulse and recorded energy.
- A second pulse page shows current/average/max measurements and configured
  target zone when available, without reporting a stale sensor sample as
  current.
- The vertical Watch pager still includes native Now Playing and the
  existing pause/end controls. Reduced-luminance Always-On remains the
  separate low-power read-only dashboard.
- Optional Watch launch disclosure "More activities" exposes cycling, HIIT,
  functional, rowing, stairs, yoga and generic activity types supported
  by WatchWorkoutManager's existing HealthKit configuration pathway.
- iPhone Watch-mirroring shows activity-specific heading and workout-time
  hero for these modes, keeping measured cycling distance dominant.
  Active Watch session ownership and all workout controls are unchanged.
- The UI deliberately avoids fabricated HIIT rounds, rowing strokes,
  exercise reps, stairs and unmeasured movement speeds.
- Release gate: macOS Xcode watch/iOS build, small/large Watch layout,
  HealthKit exercise-type capture, Live Activity continuity, phone
  mirroring and on-device battery checks. None are claimed complete solely
  from this source change.

## Phase 8 — accessibility and readability (increment 1)

- Replace the unsupported watchOS disclosure control in the start flow
  with an accessible expand/collapse button. Keep running, walking and
  strength prominent while exposing all other HealthKit activity types.
- Add a Foundation-only spoken metric formatter for duration, distance
  and pulse; screen readers get meaningful units rather than unexplained
  clock punctuation and bpm abbreviations.
- Do not announce invalid, unrecorded or stale sensor values as zero or
  as live measurements. Unit tests cover Norwegian/English spoken values,
  empty pulse, NaN and infinity.
- Make Watch sport, interval, Ghost gap and running pulse headline fonts
  scale with the user's preferred Dynamic Type size.
- Give key metric surfaces explicit VoiceOver labels/values while
  preserving the visual presentation for users without assistive tech.
- This is a presentation-only increment: workout timing, HealthKit,
  transfer commands, route/Ghost logic and existing controls remain intact.
- Final phase 8 gate: compile/watchOS and iOS tests, physical Watch
  screenshots, VoiceOver navigation, high-contrast checks,
  large Dynamic Type, reduced-motion and wrist-down battery behavior.

## Phase 8 — personalized Watch views and Always-On privacy (increment 2)

- Reuse the existing Live Workout surface configuration and its normal
  iPhone → Watch transfer. Four optional, backwards-compatible settings:
  preferred run primary metric (automatic/pace/distance), preferred initial
  run page (live/pulse/audio), high contrast and private Always-On.
- Default settings preserve the current run pace-first, walk distance-first
  and live-metrics initial page hierarchy. If Audio Coach is not configured,
  requesting its first page safely falls back to live metrics.
- In the existing Widgets & Surfaces settings, display all four options
  with immediate persistence and the established WatchConnectivity send.
  Older persisted JSON safely decodes with nil optionals and default behavior.
- The interactive Watch run hero orders the two metrics according to the
  preference. Initial page selection changes only navigation, never
  workout recording/elapsed time or sensor ownership.
- Contrast opt-in strengthens labels on the Watch live metrics and
  low-power Always-On screen.
- Always-On privacy mode, opt-in, shows only activity category and workout
  elapsed time while the wrist is down. It hides exercise names, interval
  targets, heart rate, route names and ghost gap until the Watch wakes.
- Tests cover defaults, custom priority, unavailable Audio Coach fallback,
  privacy/contrast and old configuration decoding. Device and battery
  acceptance gates still apply before a release is declared validated.
