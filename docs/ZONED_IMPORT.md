# Zoned to ATHLTH offline training import (2.0.1)

Source: https://github.com/alarboulletmarin/zoned (MIT; copyright 2026 alarboulletmarin). The redistributed MIT notice is bundled in ATHLTH/Resources/Zoned-LICENSE.txt. We import structured content, not the upstream app, proprietary Garmin FIT SDK, icons or fonts.

## Bundled snapshots
- ZonedPlansA.json and ZonedPlansB.json: 10 source plans, 116 weeks, their actual sessions, training phases, optional strength suggestions, distance targets, load scores and pace examples.
- ZonedWorkoutsA.json and ZonedWorkoutsB.json: 250 source workout definitions; 230 running + 10 cycling workouts are offered. Ten swimming workouts remain in snapshot only, pending a swim engine.
- Offline resources: no runtime HTTP request, API key, or subscription.
- The prescribed weeks are scheduled as-is (not rebuilt from the first week's generic recipes), with the user's preferred training days. Strength suggestions are not silently scheduled.
- The race-day sentinel is preserved as an executable event.

## Heart-rate intensity zones
Zoned uses six HRmax bands: Z1 50-60%, Z2 60-70%, Z3 70-80%, Z4 80-90%, Z5 90-95%, Z6 95-100%. ATHLTH uses five measured bands, with its final Z5 spanning 90-100%.

Every imported block retains the unmodified source-zone label (including ranges), source percent lower bound and upper bound, as well as an ATHLTH zone where conversion is unambiguous. Source Z5 and Z6 both fall inside ATHLTH zone 5, but the original percentage bands stay separate. Crossing ranges such as Z1-Z3 do not become a fake single-zone prescription.

The current workout-details UI displays the source range and HRmax percentages. Future zone-triggered live alerts must consume the stored percent range and a calibrated athlete-specific HRmax. A planned zone is never measured HR.

## Other workout details
Workout steps preserve chronological warm-up, effort, nested interval repeats, interval recovery and cooldown. We keep coaching tips, common mistakes, phase, recovery weeks, key sessions, weekly kilometre goals, workout target duration and source load scores.

Example source paces are not individual prescriptions. ATHLTH deliberately leaves live target pace unset until calibrated. Source load scores retain their Zoned label and are not treated as HealthKit measurements. Some prebuilt sessions prescribe scaled repetitions different from the generic workout template; the difference is flagged in the session notes for manual review rather than silently misrepresenting the source schedule.

The source's return-from-injury plan is general fitness content, not medical rehab advice.

## QA
Tests/ATHLTHZonedPlanImportTests.swift tests counts, parsing, source sessions including race days, six-zone percentages, interval recovery and cycling. An iOS build and XCTest against the final commit are required before TestFlight. This change does not trigger a TestFlight upload.
