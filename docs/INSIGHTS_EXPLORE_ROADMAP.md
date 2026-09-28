# ATHLTH Insights + Explore implementation plan

Target: `release/v1.4.4`

## Product structure

Final primary navigation:

1. Home — today, active goal, activity and shortcuts
2. Train — plan, quick start, calendar and training library
3. Insights — recovery + progress + interpretation
4. Explore — location-aware routes, events and challenges
5. Community — people, groups, feed and social interaction

Profile remains outside the tab bar.

## Safety rules

- Preserve the existing Recovery and Progress views as deep-detail destinations until Insights has feature parity.
- Reuse existing HealthKit, route discovery, challenge, social and Ghost Race stores. Do not create duplicate sources of truth.
- Keep tab indexes stable at five items. Community remains tag 4. Train remains tag 1.
- Audit all hard-coded tab navigation when Progress moves from tag 3 into Insights at tag 2.
- New interpretation must be explainable. Avoid medical diagnosis or promises about performance.
- Health insights remain local unless the user has explicitly enabled existing Coach health-data sharing.

## Step 1 — Navigation foundation

- Replace Recovery + Progress tab entries with Insights + Explore.
- Keep Recovery and Progress reachable from Insights as detail screens.
- Fix Home shortcuts that previously pointed to Progress.

Acceptance:
- Five tabs render as Home / Train / Insights / Explore / Community.
- Existing remote-notification routing to Community continues to use tag 4.
- Home “This week” and health-insight actions land on Insights.

## Step 2 — Insights foundation

Build a new Insights screen around three user questions:

- NOW — what is happening now?
- TREND — what has changed over time?
- WHY IT MATTERS — what should the user understand or consider doing?

Components:

- ATHLTH Pulse: Strong / Balanced / Recover / Learning.
- Current recovery, sleep, HRV and resting-HR signals.
- 28-day training trend vs previous 28 days.
- What Changed detection for meaningful changes.
- Explainable “Why it matters” card.
- Deep links to full Recovery and full Progress.

Acceptance:
- Works with Apple Health connected.
- Degrades gracefully without Health permission/data.
- Existing detailed Recovery/Progress functionality remains available.

## Step 3 — Training intelligence

- Add What-if training simulator.
- Use the user’s current average session duration as the baseline.
- Let the user model 2–7 sessions/week.
- Include scenario focus options such as Consistency, 5K and Half Marathon.
- “Build this plan” routes into Train; it must not silently change the active plan.

Acceptance:
- No medical/performance prediction claims.
- Simulator is useful even before AI is involved.

## Step 4 — Replay / race yourself

Promote the existing Ghost Replay system into Insights:

- Race my previous run.
- Replay/simulate a historical outdoor run.
- Keep existing Ghost Race source of truth and privacy behavior.

Acceptance:
- No duplicate ghost/replay engine.
- Existing Ghost Replay simulator remains the implementation behind the new entry point.

## Step 5 — Explore

Promote the existing Around You system into a first-class tab.

Initial map layers:
- Routes
- Events
- Location-aware challenges
- User location

Supporting discovery:
- Public/upcoming challenge cards
- Nearby route leaderboard/detail access
- Community activity discovery where current privacy rules allow it

Acceptance:
- Tab bar stays visible when Explore is a root tab.
- Home can still open Around You as a focused full-screen destination.
- Location access stays opt-in and follows the existing permission flow.

## Step 6 — Home integration

- Home remains lightweight.
- Surface ATHLTH Pulse/insight summary instead of duplicating all Insights.
- Preserve Today, Activity, Goal and Around You.
- Ensure links use new tab destinations.

## Step 7 — Validation

- Run the existing iOS/Swift 6 build workflow.
- Run regression/unit tests.
- Check iPhone and iPad navigation.
- Verify Home → Insights, Home → Community, Explore map, Recovery detail, Progress detail and Ghost Replay.
- Do not upload to TestFlight as part of this implementation unless explicitly requested.
