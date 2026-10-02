# ATHLTH 1.3.9 Hardening Checklist

This checklist is intentionally separate from TestFlight deployment.  
**Do not upload 1.3.9 to TestFlight until explicitly approved.**

## Automated status

- [x] Xcode 27 / XcodeGen project generation
- [ ] Final iOS Simulator build on current `release/v1.3.9` head
- [x] Profile privacy entry consolidated
- [x] Settings privacy entry removed
- [x] Duplicate Social privacy toolbar entry removed
- [x] Internal System Diagnostics added
- [x] Home live map removed in favor of deferred snapshot
- [x] Home location changed to one-shot discovery request
- [x] Home social loading reduced/cached
- [x] Home / Community use lazy content loading
- [x] Recovery / Progress / Profile heavy content switched to lazy loading
- [x] Home can continue an active mirrored Apple Watch workout
- [x] Home no longer presents a disabled Run start sheet when Apple Watch is unavailable
- [x] Empty Profile goal state links to Goals
- [x] Messages has New Message flow and message-request handling
- [x] Community leaderboard uses only activity already visible to the viewer

## Physical iPhone pass

### Home
- [ ] Cold launch feels responsive
- [ ] Hero renders immediately without jump/flicker
- [ ] Content scrolls independently below pinned hero
- [ ] Today shows the correct planned workout
- [ ] Strength Quick Start works on iPhone
- [ ] Run Quick Start starts on Watch when Watch is ready
- [ ] Run without Watch routes to Train instead of a disabled dialog
- [ ] Move / Recovery / Sleep display correctly
- [ ] Activity Center loads without blocking scroll
- [ ] Around You snapshot appears only when scrolled near it
- [ ] Pull-to-refresh does not cause duplicate cards or repeated navigation

### Train
- [ ] Today / Plan / Library switching is immediate
- [ ] Plan workout opens correct details
- [ ] Strength start respects iPhone / Apple Watch choice
- [ ] Saved workout templates open/start correctly
- [ ] No-plan state routes to Programs
- [ ] Routes preview does not cause noticeable scrolling lag

### Recovery
- [ ] Readiness score agrees with underlying breakdown
- [ ] Sleep / HRV / resting HR explanations are understandable
- [ ] Muscle recovery / soreness flow works
- [ ] No-Health / baseline-building state is useful and not empty
- [ ] Recovery tools open and dismiss correctly

### Progress
- [ ] Week / Month / 3 Months / Year all load
- [ ] Overview metrics drill into the expected detail
- [ ] Running and strength records are not duplicated
- [ ] No-Health state still shows ATHLTH-native strength progress
- [ ] Scrolling remains smooth with a long history

### Community
- [ ] Friends / Community leaderboard switching works
- [ ] Week / Month switching works
- [ ] Consistency / Workouts / Running values are plausible
- [ ] Challenge shortcut opens with the correct friend preselected
- [ ] Events open correctly
- [ ] Friends Activity only shows actual friends
- [ ] Discover People Add/Pending/Friends state is correct

### Profile / Privacy
- [ ] My Gear is one compact horizontal row
- [ ] Privacy shield appears beside Settings
- [ ] No Privacy entry remains in Settings
- [ ] Profile / messages / activity / route privacy values persist
- [ ] Avatar upload works and accepts files up to 10 MB in 1.3.9
- [ ] Empty goal state opens Goals

### Messages
- [ ] Plus button opens New Message
- [ ] Friend starts a direct conversation
- [ ] Non-friend sends only one request before acceptance
- [ ] Accept / decline / block works
- [ ] Unread badge clears when thread opens
- [ ] Read state updates on sent messages

## Apple Watch pass

- [ ] Watch app installed/paired state is correct in System Diagnostics
- [ ] Start Run from iPhone launches Watch workout
- [ ] Start Walk from iPhone launches Watch workout
- [ ] Start Strength from iPhone launches Watch workout
- [ ] Live Watch workout mirrors to iPhone
- [ ] Home shows Continue Workout while mirrored workout is active
- [ ] Pause / resume / end commands work
- [ ] Completed workout appears in Apple Health
- [ ] Completed workout appears in ATHLTH Activity / Progress
- [ ] Route is returned for outdoor run/walk when available
- [ ] Goals / challenges / trophies update once, without duplicates

## iPad pass

- [ ] Onboarding shows the same required controls as iPhone
- [ ] Portrait layout has no clipped hero/buttons
- [ ] Landscape layout has no clipped hero/buttons
- [ ] Pinned heroes remain visually correct
- [ ] Main content respects 760/900 pt max-width layouts
- [ ] Sheets and forms remain usable with keyboard visible

## Diagnostics

Settings > Developer > System Diagnostics should be checked after physical-device tests.

Verify:
- Health last successful sync
- Watch paired / installed / WCSession status
- Push/APNs backend registration
- App version + build
- No persistent Health / Watch / push errors

## Known performance asset follow-up

These source/runtime assets are much larger than the newer hero assets and should be optimized before broad distribution while preserving the master originals outside the runtime asset bundle:

- Onboarding hero: ~16.3 MB
- Train hero: ~5.5 MB
- Community hero: ~4.2 MB

Target: keep high-resolution masters, but ship appropriately downsampled runtime assets for phone/tablet display.

## Release gate

1. Final branch-head CI build is green.
2. Physical iPhone pass has no blocker.
3. Apple Watch end-to-end workout pass has no blocker.
4. iPad onboarding/main-tabs pass has no blocker.
5. No new privacy/RLS issue is observed.
6. TestFlight upload only after explicit approval.
