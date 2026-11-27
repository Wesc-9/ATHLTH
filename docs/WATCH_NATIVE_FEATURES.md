# Watch native feature rollout

## First increment
- Double Tap on existing start set, active rep set completion, finished timed set, completed rest, warmup advance and free-run lap controls. Never end a workout or automatically shorten rest with a gesture.
- Read exact HealthKit workout heart rate zone durations and thresholds (watchOS 27+) from the saved workout, preserve them in the result transfer, and show native durations in the existing summary. Existing ATHLTH live targets remain unchanged until one immutable zone configuration is shared with phone, iPad, coach and Garmin. No retroactive recalculation.
- Siri phrases use existing workout start intent; validate language/device recognition on hardware.

## Next increments (not yet implemented)
- Native preferred zone selection before beginCollection, explicit custom zone override, immutable snapshot through mirror and coach, older-OS fallback and settings.
- Control Center and Smart Stack: shared navigation intent, account-safe cached schedule relevance; no duplicate launch path.
- AI Coach: explicit opt-in, supported entitlement and model availability, network fallback, no silent health-data submission or autonomous control of workout.
- MapKit directions only on explicit request; existing cached route and offline guidance remain authoritative.
- Bluetooth: use system-paired HR where available, explicit sensor pairing with measured data provenance and no duplicated HealthKit samples.
- Repetition detection: opt-in motion sampling only in active compatible sets, confidence-based suggestion, manual confirmation, benchmark by exercise and wrist.
- WorkoutKit: explicit export of accurately representable plans; preserve ATHLTH session identity and do not double-import Apple workouts.

All new API integrations require Xcode 27 build and real Watch verification. The iPhone companion remains mandatory.
