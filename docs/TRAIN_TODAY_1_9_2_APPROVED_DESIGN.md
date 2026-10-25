# ATHLTH Train – I dag redesign / decisions in release/v1.9.2

Updated: 2026-10-25. Baseline: release/v1.9.2.

## Purpose and release policy
This is the authoritative implementation checklist for the agreed Train redesign. The Home tab and the global bottom navigation must remain unchanged. Keep edits reversible and isolated. Design approval does **not** authorize TestFlight uploads.

## Approved design and information hierarchy
1. Bright training-related photographic hero, consistent with Home's warm, airy visual system. No oversized decorative sculpture or dominant ATHLTH wordmark.
2. A compact floating translucent top-right navigation capsule with **I dag · Plan · Fremdrift**, inspired by Home's top-right menu. The active icon/label uses subtle warm gold. The menu belongs naturally to the hero, not a second global tab bar.
3. Show **Aktiv plan** only if a plan exists, compactly displaying title, current week and truthful plan progress; tap opens the plan.
4. **Dagens økt** is the dominant action card, with the correct session title, workout-specific metadata, thumbnail, details and an accessible Start/Continue action. Do not show an extra “Neste i dag” section.
5. **Start en økt** has a 2×3 quick-start selection: løping, gå, styrke, sykling, yoga and egendefinert. Order by the user's *previous taps* (not completed-session count); have stable default order and a way to access all activities. Do not let stored preferences block an activity.
6. **Aktivt mål** and **Dagens fokus** below. Avoid duplicating Home's Ukens fremdrift or Friends sections. The athlete selected **C – personalized intelligent goal spotlight**: the saved primary goal stays primary. A relevant, explicitly active goal may be offered for today's verified workout category. Only a manual on-screen tap temporarily highlights it; "Hovedmål" restores the original view. No goal persistence or primary-goal mutation. Do not suggest mismatched, paused, completed or foreign-plan goals.
7. When there is **no planned workout**, the primary card uses a situational blend of a relevant suggestion, a repeatable earlier workout and discovery – based only on available data, without inventing readiness or historical performance.

## Navigation behavior
- The Train navigation is separate from the unchanged global tab bar.
- Scroll down: hide the Train capsule with a smooth motion; scroll up: reveal it again. Use a movement threshold/debounce to prevent jitter.
- Within a single visit to Train, preserve each section's own scroll position. When Train is left and opened later, start at the top. This never resets a draft, recorded workout or other user data.
- Keep taps and voice-over labels accessible and maintain sensible behavior with larger text and reduced-motion settings.
- Train's Plan and Fremdrift share the same navigation language; no unrequested large rework of their content.

## Live primary card – approved option C
- **A workout is active:** the primary card on Train → I dag becomes its live presentation rather than adding a competing floating return card.
- Use the appropriate underlying active workout and device session; show a clear **Fortsett økt** action that returns to the existing recorder, never starts a second session.
- **Run/walk:** show live duration, measured heart rate if available, pace and distance if reliable; running intervals may show current repetition/rest and target.
- **Strength:** show live duration, measured heart rate if available, current exercise, set/reps and rest state when available.
- **Other activities:** show common duration and activity-specific metrics that actually exist; omit unknown fields.
- Do not present missing values as measured, nor blend manually estimated and measured values without labeling.
- Upon finish, show a completed state / accessible summary, without declaring an unrecorded session complete.
- Continue from whichever device controls the active workout, respecting Watch mirroring and recovery checkpoints.

## Delivery / validation tracking
- [ ] Compact visual Train navigation integrated with the hero.
- [ ] Smart show/hide and per-section scroll restoration.
- [x] Today hierarchy: compact active plan and dominant daily session; removed redundant next-session panel (implemented; visual QA pending).
- [x] 2×3 quick start, persistent tap-based sorting (implemented; build verification pending).
- [x] Active goal and daily focus, with reversible contextual suggestion (implemented; build verification pending).
- [ ] Contextual card when no session is scheduled.
- [ ] Workout-type live primary card, including Watch/strength/run fallback.
- [ ] Verify navigation transitions, no duplicates, reduced motion, long text, workout resume.
- [ ] Build + unit/UI verification, then request explicit permission separately for TestFlight.

Do not mistake this checklist for implementation completion. Tick off items only when code and validation support them.
