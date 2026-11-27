# AirPods integration (3.0.6)

## Delivered foundation
- AirPods entry in Health & connections, using the actual selected audio route (not a pairing or heart-rate claim).
- All generations can use the native route picker and existing Audio Coach/Siri functions; renamed AirPods may be manually remembered on this device.
- Motion support is verified by an explicit short Core Motion test. No raw motion samples retained, no continuous scan, no microphone activation.
- AirPods Pro 3 heart rate is hardware-dependent; audio-route names do not establish sensor availability.

## Remaining release gates
- Integrate a single iPhone/iPad HKWorkoutSession + HKLiveWorkoutBuilder with the existing recording arbiter and final HealthKit save path. Do not start a parallel workout alongside Watch or the existing builder. Preserve local workout IDs, routes, pause events, recovery and import deduplication. Validate running, walking, strength and sport separately. Publish timestamped current pulse only from observed samples, never infer source from audio name; do not promise cadence or sensor source if unavailable.
- Reuse the verified pulse for zones, coach and summaries; use system energy data when available without double counting. AirPods loss must never stop the workout. Watch mirroring remains unchanged until hardware-tested.
- Extend workout App Intents through existing launch admission and controls; authenticate and test locked-screen access. No permanent microphone.
- Activity classification, head gestures and motion/ML analysis remain experimental: explicit opt-in, admin-only until validated, per-model API availability and permission, no unsafe automatic pause/end, no cloud/raw motion persistence, stop at workout end. No unvalidated gait/form or fatigue claims.
- Device tests: AirPods 1/2, AirPods 3/4, AirPods Pro 1/2/3, Max, renamed route, non-AirPods, phone-only and Watch, iPad, Bluetooth loss/reconnect, permission denial, locked screen, Spotify resume, no duplicate workouts. Xcode build and physical device test required before feature activation.
