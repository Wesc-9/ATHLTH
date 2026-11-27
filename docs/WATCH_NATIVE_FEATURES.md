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

## Control Center and schedule relevance
- Five watchOS 26+ system controls open the existing planned, daily form, sent, Ghost and favorites destinations via a shared OpenIntent. Active workout presentation is not interrupted.
- The existing Today widget provides a date-based Smart Stack relevance window around the next cached eligible planned workout. The shared projection contains a date only and clears on account changes. Location and invitation context are future extensions.
- Corrected the obsolete Community header audit signature to the actual cover(onArtwork:) method, keeping the rest of the layout audit intact.

## Native live heart-rate zones: staged rollout
- A free Watch workout without an explicit target, structured prescription or active Audio Coach captures the actual HealthKit builder zone configuration. The same thresholds drive the Watch and mirrored phone/iPad gauges. No extra sample query or timer. Older OS and unavailable configurations fall back to ATHLTH.
- Existing structured and coach workouts retain ATHLTH live-zone semantics pending a complete migration of authored targets and custom coach triggers. Apple recorded duration data stays source-labelled and separate. Explicit user settings and native coach integration remain outstanding.

## Coach follow-up
- Free-workout measured-zone speech and periodic readouts use the same native Watch thresholds on both voice owners. Explicit zone-trigger rules, preferred zone targets and structured sessions keep existing authored ATHLTH scale. No language model runs in the live control path.
- Fixed the ControlWidget initializer conformance reported by CI. New build confirmation remains required.

## Watch AI Coach reflection
- Existing live Coach menus and completed summary offer an explicit read-only reflection. Measured facts are displayed locally and unavailable values are omitted. Optional Apple PCC selects only an approved focus from coarse activity context after per-request consent; no raw pulse, exact distance, route, identity or history is submitted. No workout mutations, automatic requests, or background polling. Missing model/network/entitlement returns local feedback. The managed entitlement is deliberately not added to signing until Apple grants it. Conversation, comparative history, motion ML and editable adaptation proposals remain separate work.
