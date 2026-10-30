# ATHLTH Android foundation

Status: architecture decision and first integration plan, **not an implemented Android app**.
Date: 2026-10-30
Starting iOS baseline: `release/v2.0.4` (commit `a2f573d54111fdf7145a3da0454e0382de800b4a`).
Working branch: `feature/android-foundation`.

## Decisions

1. Preserve the existing iOS SwiftUI and watchOS projects without a rewrite.
2. Build Android with Kotlin and Jetpack Compose. Add a native Wear OS companion later, using Wear OS Health Services for live workout sensing.
3. Use **Android Health Connect** as the canonical Android on-device *health data interchange* API. It is not a measurement app and does not replace a watch, fitness app, or sensor.
4. On Android 14+, Health Connect is integrated into Android. Older supported devices with Google Play services may need the Health Connect app installed. Check feature availability and fall back gracefully.
5. Reuse the existing Supabase project, verified user identity, database schemas, server functions, public content and brand assets as applicable. Never copy credentials from device code into a different security context.
6. Keep platform-specific interfaces for HealthKit/Apple Watch and Health Connect/Wear OS. Preserve parity of **behavior and data semantics**, not necessarily identical platform UI implementations.
7. Consider Kotlin Multiplatform for **new pure domain logic** only after measuring the actual integration cost with the existing Swift code. Do not migrate existing SwiftUI merely to create nominal shared code.

## Repository evidence to preserve

- `ATHLTH/Core/Services/ServiceProtocols.swift` already separates health data, workout recording, authentication and social service interfaces.
- `ATHLTH/Backend/SupabaseEnvironment.swift` and `ATHLTH/Backend/SupabaseBackendModels.swift` demonstrate reusable server-side account and entitlement contracts.
- `ATHLTH/Planning/TrainingBuilderModels.swift` defines workout prescription semantics that must be represented faithfully in platform-neutral wire contracts, including warmups, intervals, recovery, pacing, strength and individualized per-set parameters.
- `docs/athlth-unified-workout-engine.md` describes a stable planned workout identity, a single recording per hybrid workout, sensor provenance, and no phantom duplicate workouts.
- `docs/TRAINING_DATA_PRIVACY_RELEASE.md` says current backup is consent-based and **not two-way sync**. Cross-device plan continuity cannot be assumed until a distinct safe sync design is implemented.

## Share vs implement by platform

| Domain | Share/reuse | Android-specific implementation |
| --- | --- | --- |
| Accounts and social | Supabase identities, backend authorization, RLS, social contracts | Kotlin client, Android sign-in and session storage |
| Training plans | Workout schema, goals, templates, progression rules, exercise/catalog data | Compose screens, local persistence, serialization parity |
| Coach AI | Existing server functions and content policy, with authorized request schemas | Permission UI and explicit consent UX |
| Health | Common normalized metric contracts, source metadata, calculations when platform independent | Health Connect reader/writer, Android permission lifecycle |
| Recording | One workout/session identity; standardized phase/segment and measurement provenance | Android GPS/sensors, background recording and Wear OS Health Services |
| Community | Server data, challenges, clubs, Arena, media | Compose layouts and Android notifications |
| Purchases | Server-side entitlement checks | Google Play Billing and server verification; iOS StoreKit remains unchanged |
| Design | Brand identity, approved visuals, content, interaction specifications | Jetpack Compose, adaptive navigation, accessibility |

## Health Connect contract

- Ask only for required data-type-specific read/write grants at the moment of use.
- Initial candidates (subject to current Android API support and product need): exercise sessions, heart rate, sleep, resting heart rate, steps, distance and active calories.
- Missing or denied data means *unavailable*; never fabricate readings or treat missing metrics as zero.
- Treat Health Connect as the user-controlled on-device source for imported records; sources such as Samsung Health must be independently connected by the user to Health Connect. Record origin and timestamps for de-duplication and transparently identify imported workouts.
- Preserve the ATHLTH rule that externally recorded workouts enter the review/approval flow rather than silently creating duplicates.
- ATHLTH-recorded workouts can be written once, with stable IDs and repeat-safe logic; reading them back cannot create another ATHLTH workout. Preserve session start/end, units, zones, source, precision, and whether metrics were measured/manual/estimated.
- The platform imposes access windows and additional permissions for some historical/background scenarios. Implement an explicit history and background strategy; do not promise unrestricted access.
- Health data remains local by default. Backend sharing, training backup and Coach AI processing require their distinct existing opt-in permissions and a cross-platform consent review.
- Handle revocation, deletion, multiple sources, permissions per device, and privacy disclosures before rollout.

## Watch constraints

Health Connect does **not** provide the low-latency live watch telemetry engine. A separate Wear OS app using Health Services is required for guided live sessions, audio cues, intervals and watch interactions. Integrate phone/watch session arbitration before enabling hybrid workouts.

## Critical work before Android cross-device parity

1. Inventory local-only state versus current Supabase data. Existing opt-in backup is not two-way sync.
2. Define canonical versioned JSON data contracts for plans, prescriptions, workout events, completion, unit conversions, metric provenance, permissions and subscription entitlement.
3. Build contract fixtures from actual Swift Codable payloads; test Android decoding and round-trip compatibility without destructive migrations.
4. Implement a **consented** cross-device sync strategy with conflict resolution, offline edits, deletion and RLS tests. Never silently upload Apple Health/Health Connect raw records.
5. Make account authorization, Apple/Google login pathways and cross-store purchase verification explicit.
6. Build and test a minimal Android shell and Health Connect permission/read flow before moving complex workouts.
7. Port Train and its single-recording invariants, then Home/Insights, Profile, Explore, Community/Arena and finally Wear OS live sessions.
8. Add Android CI/build checks separate from iOS; do not touch iOS TestFlight workflow without an explicit request.

## Acceptance gates

- Existing iOS/Apple Watch behavior unchanged.
- Same account can load shared server content from both platforms.
- Opt-in training sync behavior is explicit, reliable and reversible.
- Health Connect grant/revoke and unavailable data are handled without crashes or privacy leakage.
- No duplicate ATHLTH/imported workouts or accidental reuploads on app restart.
- Live workouts preserve one session identity and measured-vs-estimated distinctions.
- Cross-store ATHLTH+ entitlement cannot be forged or granted without verified purchase.
- Android build, instrumented/on-device health integration and Wear OS behavior are verified before describing them as complete.

## Current limits

This document is an architecture baseline. It does **not** claim that the Android app, Health Connect integration, cross-device synchronization, Google Play Billing or Wear OS application has been built, compiled or tested.
