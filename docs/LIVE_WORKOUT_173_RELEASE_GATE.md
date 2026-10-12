# ATHLTH 1.7.3 — Live Workout release gate

Target: `release/v1.7.3`. Scope: phases 1–9, iPhone, Apple Watch,
Always-On, Live Activity / Dynamic Island, Ghost / Arena and Audio Coach.

**Release rule:** do not deploy to TestFlight until explicitly requested.
Successful backend tests or Swift parsing alone do **not** mean the
Watch app, widgets, runtime or battery use is validated.

## Automated gates

| Gate | Required evidence | Status |
|---|---|---|
| Backend privacy and migrations | Backend regression workflow successful at release commit | **Verify latest commit** |
| All targets compile | `Build ATHLTH` succeeds, including iPhone + Watch + widgets | **Pending complete build** |
| Unit tests | Build workflow executes `xcodebuild test`; review failures | **Pending complete build** |
| iPhone form factors | iPhone compatibility smoke passes on compact, mini, standard and large simulators | **Pending** |
| iPad | iPad compatibility smoke passes with all five tabs rendering | **Pending** |
| Live presentation invariants | Swift unit tests for pulse freshness, intervals, strength rest, Watch sync fallback and activity identity | **Added; must run** |

Do not mark any check completed because a workflow started or a syntax
preflight succeeded. Confirm the exact commit hash for each passing result.

## Physical-device acceptance checklist

Use a real paired iPhone and Apple Watch. Test both connected and offline,
and record outcome/screenshots on the next authorized TestFlight build.

| Priority | Scenario | Expected |
|---|---|---|
| P0 | Start a run on Watch while phone is unlocked | Exactly one workout session; phone mirrors it |
| P0 | Start on phone, attempt a second Watch start | No duplicated workout or HealthKit entry |
| P0 | Disconnect Watch/phone mid-run for several minutes | Watch records independently; phone labels stale data |
| P0 | Reconnect while interval or Ghost is running | Correct session resumes mirroring; no elapsed-distance reset or duplicate |
| P0 | Reconnect a different Watch workout of the same type | Old pulse, calories, distance and Audio Coach data cannot appear as initial data for the new workout |
| P0 | Deliver delayed HealthKit events from the previous mirrored session | New session status, live metrics and mirroring connection state remain unchanged |
| P0 | Complete Watch session while offline, then reconnect | Exactly one final activity; no reappearance of active session |
| P0 | Start workout B immediately after finishing A | Live Activity from A must never show B's data or dismiss B |
| P0 | Pause and resume running workout | Active elapsed time does not include pause period |
| P0 | Start, pause, resume and reset timed strength set | Countdown remains anchored across devices; no automatic completion |
| P0 | Finish strength set and wait out rest | Only manual Continue/Next advances; no duplicate set |
| P0 | Lose GPS during Arena / Live Ghost | Old lead disappears; no fabricated synchronized gap |
| P0 | Disable Live Activity in settings during workout | Display ends; underlying workout continues |
| P1 | Run + walk free session | Run pace first, walk distance first by default |
| P1 | Structured time, distance and open intervals | Remaining target shown correctly; open step does not invent countdown |
| P1 | Audio Coach enabled, muted, replay | Speech controls do not affect recording or haptics |
| P1 | User-selected first page set to Audio Coach without coach | Fallback to live metrics |
| P1 | Walk/running main metric preference changed on phone | Watch preference takes effect when synchronized |
| P1 | Always-On privacy mode while lowering/raising wrist | Only activity and elapsed time when lowered; normal data when raised |
| P1 | Always-On high contrast / large text / VoiceOver | Legible, correct descriptions; no leaking private exercise/route |
| P1 | Start cycling, HIIT, rowing, functional, stairs and yoga | Only measured metrics shown; no fabricated strokes or floors |
| P1 | iPhone compact/large and iPad | No clipped controls or overflowing image/card headers |

## Review process

1. Record the Git SHA, workflow links, iOS/watchOS builds and device models.
2. Inspect all CI results and collect exact error logs for failures.
3. If any P0 scenario fails, stop the release gate, apply a minimal reversible
   fix and rerun checks on the new commit.
4. Check P1 scenarios, VoiceOver, low-power Always-On behavior and battery
   consumption on an actual Watch; simulator output cannot certify these.
5. Release only on an explicit TestFlight request, and keep the previous
   working baseline available for rollback.

## Phase 9 implementation notes

- The Live Activity presenter must prefer the mirrored Watch snapshot when
  present, and fall back to the active iPhone workout if mirroring disappears.
  A transient loss of mirroring is not permission to close the phone workout.
- ActivityKit calls are asynchronous. An older dismissal must not reset the
  controller state of a newer Live Activity after an `await`.
- These rules are independently unit-tested where the logic is pure; actual
  cross-device connectivity and ActivityKit UI remain on the physical gate.

## Phase 9 — Watch mirroring identity hardening

- After a Watch mirror reconnect, retain cached pulse, calories and
  distance only if the previous snapshot belongs to the identical
  workout (same sport, same start time, active/preparing/paused phase).
- A new workout starts without inherited sensor values; new Watch samples
  then update the display normally.
- The HealthKit delegate checks the currently attached session identity
  before applying state, error, remote data or disconnection callbacks.
  Events queued from a previous session cannot mutate the new one.
- Unit tests cover reattach vs new session, completed/stale sessions,
  cross-sport handoffs, missing start dates and stale delegate IDs.
- Successful compilation and real reconnect/quick-restart tests are still
  required; a unit test does not prove WatchConnectivity runtime behavior.
