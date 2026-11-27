# Watch performance and Apple integrations (3.0.6)

## Implemented
- Always-On view requests 1 Hz during active strength countdowns, 5/10s for Ghost status, and keeps the idle baseline at 60s. watchOS decides the actual cadence. HealthKit samples and coach deadlines remain independent.
- Low Power Mode only reduces routine mirror traffic and free-walk GPS distance filtering; route, challenge, live share, coach and structured sessions retain full policy. No sensor sampling rates are overridden.
- HealthKit running speed can provide outdoor live pace when a valid recent sample exists; GPS remains the fallback. Running dynamics appear in the existing completed summary when the saved workout actually contains measurements.
- Action button app intents use existing Watch start admission and recorder; authorization changes require normal foreground authorization before hardware start. The next action uses the existing guarded manual interval advance or lap marker. Pause/resume use existing controls.
- Optional subjective whole-workout effort score uses the saved HealthKit workout relationship. It never substitutes set RPE or a calculated score, and never blocks workout completion.

## Required verification on physical Watch
- Build with the actual watchOS SDK; Action Button registration and first-use permission prompt on Ultra, pause/resume, next action and duplicated launch attempts.
- Compare live pace and sensor callbacks with GPS fallback on supported and unsupported models, including permission denial, auto-pause, and running indoors.
- Verify effort permission denial, successful relation, existing effort, and leaving the summary while authorization is pending.
- Measure outdoor route fidelity and battery over a fixed session, with/without Low Power Mode, at least one older and newer Watch model.
- Instrument SwiftUI view invalidation and the per-second manager loop before larger event-driven refactoring; do not change workout deadlines without device regressions.
- Inspect full independence separately: current app depends on phone provisioning/ownership and transfer queues; do not flip WKRunsIndependentlyOfCompanionApp without first-run account and identity design.
- WorkoutKit export is a separate optional interoperability project. Only workouts accurately representable by WorkoutKit should be exported, with explicit user action and duplicate-recording/import protection.
