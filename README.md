# ATHLTH

**Move better. Live longer.**

ATHLTH is an Apple Health–first training platform for iPhone and Apple Watch. The product combines health context, workout planning, routes, strength training, progress, recovery and a social layer without making private Apple Health data public by default.

## Current foundation

The repository now contains the V0.1 product foundation:

- SwiftUI iPhone/iPad app
- Home, Train, Recovery, Progress and Profile tabs
- HealthKit workout, sleep, heart-rate and route reading
- HealthKit background-delivery foundation
- Demo/preview mode so product UI can be developed before Apple signing is complete
- Training-plan domain model
- Public-catalog and private custom exercise models
- Planned workout sessions with sets, reps, load, RPE and rest
- Planned/imported route model
- Route challenge model
- Social profile, friendship, presence and messaging models
- Privacy levels: private, friends and public
- Apple Watch workout-launching service boundary
- Authentication, social, GPX import and music service boundaries

## Product tabs

### Home
Daily activity, recovery, sleep, health metrics, next workout and insights.

### Train
Quick-start workouts, advanced plans/calendar, strength exercises, routes/challenges and Apple Watch launch.

### Recovery
Sleep, HRV, resting heart rate, recovery trends and training-readiness guidance.

### Progress
Training consistency, trends, personal records and achievements.

### Profile
Unique username, social profile, friends, public/shared plans, routes, activities and optional live “Training now” presence.

## Accounts and social

ATHLTH is designed for:

- email sign-in
- Sign in with Apple
- unique usernames
- friends/following
- optional live training presence
- shareable training plans and routes
- comments/reactions first, messaging later
- private/friends/public visibility per shared object

Health metrics remain private by default. Sharing an ATHLTH activity must be explicit and separate from HealthKit authorization.

## Training plans

The plan model is designed for advanced scheduling rather than a simple workout list. It supports multiple weeks, days and sessions, with running, walking, strength, mobility, recovery and custom workouts.

Strength sessions support embedded exercise snapshots. This allows a custom exercise to remain visible inside a shared plan even when the recipient has not saved that exercise to their own library.

Nutrition/meal planning is planned as a later calendar layer rather than being tightly coupled to workout records.

## Routes and challenges

Routes are first-class ATHLTH objects:

- create a route
- import GPX
- save/share a route
- attach a route to a planned workout
- send the planned workout to the ATHLTH Apple Watch app
- record the completed route
- challenge friends or public participants on the same route

## Apple Watch

ATHLTH will include a real watchOS companion app. The service boundary for launching a workout from iPhone is already represented in the codebase. The production implementation will start/wake the paired Watch app, run the workout session, and sync duration, heart rate, calories, distance and route back into HealthKit/ATHLTH.

## Music

Spotify is planned as an optional connection. A workout or training plan can reference a playlist, while Spotify remains responsible for playback.

## Build

The project uses XcodeGen:

```bash
brew install xcodegen
xcodegen generate
open ATHLTH.xcodeproj
```

The GitHub Actions workflow also generates and builds the Xcode project for the iOS Simulator.

## Settings

The Profile tab includes a Settings control next to Share and Edit Profile. The settings foundation currently covers:

- app language: English, Norwegian, Spanish, Italian and Simplified Chinese
- metric / imperial measurements
- system / light / dark appearance
- profile and default activity visibility
- optional “Training now” presence
- route-sharing defaults and start/end privacy
- heart-rate sharing disabled by default
- Apple Health, Apple Watch, Spotify and Home Assistant connection surfaces
- workout reminders, friend activity, challenges and message notifications
- auto-pause, audio cues and Apple Watch haptics
- export, blocked users and account deletion surfaces
- diagnostics / Capability Lab

The language selector already drives the app locale. Translation strings will be filled out as the UI stabilizes so all five languages can be maintained consistently.

## Apple capabilities

The current code prepares for HealthKit background delivery. Device verification still requires the correct Apple Developer capabilities, signing and a physical device.

## Next implementation milestones

1. Stabilize and visually refine the five-tab V0.1 shell.
2. Connect the new Home/Recovery UI to live HealthKit data.
3. Add account backend and unique-username onboarding.
4. Implement full training-plan persistence/editor.
5. Add exercise catalog adapter and custom exercise creation.
6. Implement GPX route import and route editor.
7. Add the watchOS target and real “Start on Apple Watch”.
8. Add route challenges and social activity sharing.
9. Add Spotify connection.
10. Add nutrition planning after the core training experience is stable.

> ATHLTH is a working product name and has not yet been represented as a completed trademark clearance.
