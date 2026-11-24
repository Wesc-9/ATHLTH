# Shared Apple Watch and Garmin training prescription
The existing PlannedWorkoutWatchBuilder and WatchPreparedWorkoutTransfer are
canonical. Garmin's v2 compact projection preserves source/plan/session/step
IDs, the full ordered supported step sequence, target duration/distance,
phase, pace/zone metadata and auto-advance/warmup policy. No new plan builder.
Garmin executes the time/distance/open subset locally using recorded timer
and distance counters. Paused recording cannot advance. Open steps and
acknowledged targets can advance on the next-page behavior. The final step
completes the prescription but does not silently stop or save the workout.
Events carry original step IDs and monotonic sequence, with a version gate
and no cross-device acceptance. FIT save acknowledgement is still separate.
Pace/zone metadata is transported, not yet evaluated or displayed on Garmin.
Structured strength must reuse WatchStrengthSessionSnapshot and its exerciseQueue,
not a second exercise library. Remains unimplemented on Garmin.
No route, audio, ghost, treadmill, auto-pause or unsupported instruction
behavior is silently flattened; the staged projection throws rather than
starting an incomplete recipe. Some additional metadata is advisory and
needs implementation before enabling full structured launch.
32 steps / 10 KB JSON budget are conservative development limits, not SDK
guarantees. A 4x4 fits; longer prescriptions need verified chunking.
No live transport is enabled in production. SDK/Monkey C compilation,
cross-platform parity fixtures, universal recorder integration, durability,
full plan admission and physical device validation remain required.
