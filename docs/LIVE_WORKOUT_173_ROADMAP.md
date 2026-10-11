# ATHLTH 1.7.3 — Live Workout implementation roadmap

Baseline: `release/v1.7.3`. Keep recording engines, workout ownership, iPhone/Watch sync and HealthKit continuity unchanged. Make small, reversible, direct commits. Do not deploy to TestFlight unless requested.

## Phases and acceptance criteria

1. **Shared live presentation policy (in progress)** — Shared, testable hierarchy for workout phase, primary/secondary metrics, and context-dependent watch pages. AOD can consume it without touching workout recording.
2. **Apple Watch strength** — Distinct active-set, countdown, rest, exercise-queue and status pages; Crown input and explicit set completion; preserve warm-up, zero weight, resistance-level and RPE/RIR rules.
3. **Apple Watch running** — Readable pace/distance, structured interval, pulse/zone, route, Ghost/Arena, Audio Coach and controls; only relevant pages shown; no surprise auto-swipes.
4. **Always-On** — Single low-power, read-only presentation selected by activity and phase, including accurate rest countdown. No animations, sensitive details policy, stale-data treatment and small-screen testing.
5. **iPhone live workout** — Activity-first hero metric and details, aligned with Watch; strength, run, treadmill, intervals and companion mode.
6. **Lock Screen / Dynamic Island** — Use existing Live Activity infrastructure and phase-specific compact/expanded variants; terminate cleanly when workout ends.
7. **Other workout modes** — Walking, HIIT, cycling, functional, rowing, stairs, yoga; never show irrelevant or unmeasured metrics.
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
