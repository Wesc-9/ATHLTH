# ATHLTH Adaptive Training – coordinated delivery contract (1.7.4)

Status: implementation in progress. This document defines the work; listing a capability here does **not** mean it is implemented or tested.

## Non-negotiable product rules

1. Design first: new plan screens use `ATHLTHPlanDesign` tokens and shared components (rather than hand-picked colors/radii); run the internal Plan Design Lab and review iPhone, iPad, Dynamic Type, VoiceOver, empty states, long names, errors and contrast.
2. One plan model: simple, advanced, manual, imported template, AI and Coach changes all converge on the existing `TrainingPlan` / `TrainingPlanBuilderProfile` persistence. Do not introduce another plan store, workout engine or shadow schedule.
3. One workout identity: planned session IDs must survive plan → phone/Watch → workout history → progress → adaptive suggestions. Dedupe imported HealthKit/Watch evidence.
4. Never rewrite workout history or completed/skipped sessions. Preserve version checks on all plan mutations; present conflicts for reconciliation rather than silently overwriting a newer version.
5. AI is opt-in. A generated or adapted plan is a draft until the user reviews and accepts it. Preview the *whole* program, not just a few representative weeks; support editing and undo.
6. Injury and health details are sensitive; collect minimally, distinguish device/local processing from third-party AI and obtain a separate, informed opt-in before transmission.
7. Training and recovery estimates are not medical diagnoses and must not imply unsupported certainty. Lack of data should be visible, not replaced with invented scores.
8. Keep Quick Run, live strength, Apple Watch and Audio Coach launch/recording engines intact. No TestFlight upload without a separate explicit user request.

## Release gates

Each phase needs:
- **Design:** reusable components, typography, hierarchy, compact and regular density, easy tap targets, iPhone/iPad snapshots, accessibility and localization.
- **Behavior:** no dead ends, functional back/cancel, preserved unsaved drafts where appropriate, error and offline states.
- **Data:** test correct persisted plan/session identity, concurrency/version checks, plan/actual reconciliation and no fabricated metrics.
- **Safety:** independent training-rule validation before AI recommendations are applied.
- **Performance:** scroll and launch regressions monitored; avoid growing existing multi-thousand-line views with large new subflows.

## Delivery sequence

### 0. Design foundation and canonical entry (STARTED)
- Central plan palette, spacing, depth and reusable choice/surface components.
- Debug-only Plan Design Lab using production components, with no user data mutations.
- Route Train's former second composer through the canonical plan builder.
- First-screen selection between **Enkel** and **Avansert**.
- Create name, duration, start date and choose blank, saved or catalog source.
- Testable route policy: short simple path, detailed advanced path.
- Remaining: whole-plan visual overhaul, remove deprecated composer logic after build/QA, plan identity handoff for saved/catalog sources, screenshots and device verification.

### 1. Reliable program studio
- Draft saving/resume (without accidental activation), intentional activation after preview.
- High-level plan, weeks, days and editable workouts in one navigable studio.
- Keep existing running, strength, interval and route workout configuration and reuse its exercise catalog.
- Copy/move/edit with expected plan version and explicit behavior for completed sessions.
- Empty/error/long-plan states, saved-plan/template copy independent from original.

### 2. Personalization and safety
- Optional baseline calibration from existing workouts, weights, distances, pace or user input; never require unsafe max tests.
- Primary/secondary focus, explicit goals, equipment, schedule, weekly time and exercise preferences.
- Shared strength + running schedule advisor; detect likely scheduling conflicts and offer options.
- Separate pure deterministic program validation (range, distribution, recovery spacing, equipment and exercises).

### 3. AI and explainability
- Manual, AI-assisted and whole-program AI paths feeding one plan model.
- AI may propose sessions per week only when that setting is explicitly delegated; respect hard constraints.
- Validate AI output before showing it; edit every week/day/set before approval.
- Explain why each workout exists; display changes and previous/next versions; allow rejecting/undoing.
- Explicit consent for personal health/injury information and error/fallback path with no AI.

### 4. Plan vs reality and insight
- Stable correspondence across planned workouts, recorded strength/run, Apple Health and Watch; offline/idempotent merge.
- Metrics split into planned, completed, skipped and shortened; show provenance/confidence.
- Goal checkpoints, comparable sessions, progression, strength volume, distance/pace, adherence and trends.
- No unvalidated probabilities or pseudo-precise recovery or injury risk scores.

### 5. Adaptive coaching
- Per-session feedback (difficulty, technique, preferences) plus observed data.
- Propose conservative, explainable, reversible next-session adjustments; opt in to apply.
- "I only have 25 minutes" adaptation preserves the purpose of the workout and records shortened completion.
- Reasonable rescheduling when strength/run load overlaps; no deterministic medical advice.

### 6. Integrations
- Home, Train, Coach, Audio Coach, Watch and Community training together consume the same plan and session identities.
- Training reminders and event scheduling cannot duplicate planned activities or cause stale sync.
- Reconnect/retry/offline behavior tested on real devices.

### 7. Later differentiation
- Personal preference learning with transparent user override.
- Trainer sharing/permissions and optional team programs, built only after single-user fidelity is proven.
- Cohort user testing of creation time, navigation errors, completed-program adherence and useful insights.

## QA / rollback

- Prefer small commits on `release/v1.7.4`, never on locked release branches; revert each slice individually if necessary.
- Existing `Tests/ATHLTHTrainPlanStudioIntegrationTests.swift` protects plan version, copied set identity, move rules, completion and history. Extend around AI approvals, synchronization and rescheduling.
- `Tests/ATHLTHPlanJourneyTests.swift` verifies route stages and basic design constraints.
- A code commit is not an iPhone/Watch quality sign-off. Verify Xcode CI and test manually on real devices before calling a phase complete.
