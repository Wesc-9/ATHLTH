# ATHLTH 1.7.3 — Visual & Battery Acceptance Gate

Scope: Live Workout on Apple Watch, iPhone mirroring, Always-On, VoiceOver,
Dynamic Island, Ghost/Arena and strength countdowns.

**Important:** The source/CI audit does not measure real battery discharge or
inspect the pixels of actual watchOS workout screens. Keep these physical
acceptance cases **OPEN** until screenshots and energy logs are reviewed.

## Automated checks

| Check | Evidence | What it proves |
|---|---|---|
| iOS/watchOS + widgets build | Successful `Build ATHLTH` run for exact commit | Sources compile and test suite passes |
| Watch visual/power static guard | `python3 scripts/audit_watch_visual_power.py` | No AOD-owned animations/timers, periodic refresh requests at >=60s, privacy and compact-layout rules |
| iPhone screenshots | iPhone Compatibility Smoke Test artifacts | Onboarding and five top-level tabs are nonblank on compact, mini, standard and large iPhones |
| iPad screenshots | iPad Compatibility Smoke Test artifacts | Onboarding and five tabs are nonblank on tested iPad |
| VoiceOver unit tests | XCTest in `ATHLTHWorkoutAccessibleMetricTests` | Spoken units and missing sensor data rules |

Automated smoke screenshots **do not** prove a live workout screen fits on a
Watch or that a workout can actually start. The Watch/iPhone workflow is only
marked complete once its separate device matrix has been tested.

## Watch visual checklist (on device)

Capture at least one screenshot per type from the active, wrist-raised screen
and a wrist-down state (where watchOS permits it), on the smallest supported
Watch and one large Watch. Use short/long Norwegian and English labels.

| Screen | Visual acceptance |
|---|---|
| Run free | Pace first by default, distance visible, time and pulse legible, no cropped text |
| Walking | Distance first by default, pace accessible, pause state unambiguous |
| Time/distance/open interval | Remaining target, current step and progress visible; no false countdown on open intervals |
| Strength reps | Exercise, set/reps and weight legible at a glance |
| Timed strength | Countdown visible, paused/expired state clear, no automatic next set |
| Strength rest | Rest/ready and manual Continue indication visible without overlap |
| Pulse | Current, average, max distinguishable; stale sensor reads unavailable |
| Ghost/Arena | Valid gap/lead, delayed GPS and paused statuses visually distinct |
| Cycling / HIIT / rowing / yoga | Only recorded metrics, no fabricated speed/strokes |
| Always-On / private | AMOLED black, activity and time only in private mode, sensitive route/health details hidden |
| Audio Coach / controls | Labels distinguish Play, Pause, Mute, Replay, Stop; no accidental Stop hit area |

Check standard and accessibility-large text, high-contrast mode, light/dark,
VoiceOver traversal, reduced motion and both metric preference orders. No
main metric may disappear behind the curved Watch border.

## Battery measurement protocol (physical Apple Watch required)

1. Use the same Watch, watchOS version, battery health, sensor permissions,
   screen brightness, wrist and training location; start each measurement
   after the Watch has stabilized and with similar battery charge.
2. Record Watch model, OS, screen brightness, AOD on/off, cellular/Wi-Fi,
   GPS status, Audio Coach, Ghost and starting/ending battery percent.
3. Run **three 30-minute outdoor running sessions** with AOD on. Compare
   with three equivalent sessions using the prior approved ATHLTH build
   or the built-in Workout app under comparable conditions.
4. Repeat with a **30-minute strength session** including sets and pauses;
   run one AOD-private and one standard AOD scenario.
5. Calculate drain percentage-points/hour:
   `(battery_start_percent - battery_end_percent) / duration_hours`.
   Keep per-run measurements; percent readings are coarse and will vary.
6. Inspect Xcode Instruments Energy Log / Power Profiler, where supported:
   display wakeups, CPU/GPU, location, background transfers and network
   bursts. Check Watch temperature, low-power behavior and whether speech
   produces abnormal wakeups.
7. Capture the screen at 5, 15 and 30 minutes. Note whether active-workout
   countdown stays accurate when raised; Always-On may show a rounded,
   throttled value until its next permitted update.
8. Flag any crash, duplicate HealthKit session, unplanned screen wake,
   rapidly repeating haptic/audio cue or Ghost/GPS refresh loop as P0.

**Release decision:** Record the comparison data and investigate any
consistent materially worse battery drain or thermal behavior. Do not invent
a battery-life estimate or call this test passed without measurements.
The existing HealthKit session must keep running in low luminance: throttling
applies to presentation requests only, never workout capture or alarms.

## Implementation audit

- Reduced-luminance countdown / Ghost `TimelineView` uses one shared >=60s
  presentation interval; no independent timer or animation is added.
- Interactive pages retain the normal responsive interval/status cadence.
- Main workout tiles support compact geometry, `minimumScaleFactor` and
  spoken units. Contrast checks are a static approximation, not a screen
  photograph or brightness measurement.
- The build workflow runs the source guard on every pushed commit.
