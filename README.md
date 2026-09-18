# ATHLTH

**Your private training companion.**

ATHLTH is an Apple Health–first training app. V0.1 is intentionally local-first: no ATHLTH account, no cloud backend, no analytics SDK, and no Home Assistant dependency.

## V0.1

- iPhone + iPad SwiftUI app
- Apple Health authorization
- Running, walking, and strength workouts
- Outdoor GPS routes when HealthKit provides them
- Duration, distance, pace, calories, average/max heart rate
- Sleep duration and stages
- Heart rate, resting heart rate, and HRV
- Train screen for Run, Walk, or Strength
- Strength splits: Full Body, Push, Pull, Legs, Upper, Lower, Custom
- **Capability Lab** for Personal Team device testing
- English-first localization structure
- Privacy-first, on-device architecture

## First device test: free Personal Team

We are using free direct-to-device development before paying for TestFlight.

See **[PERSONAL_TEAM.md](PERSONAL_TEAM.md)** for the Mac/iPhone installation steps and the in-app capability test order.

## Privacy

V0.1 has no ATHLTH account, cloud backend, advertising, third-party analytics, or Home Assistant connection. Health data is read directly from HealthKit and remains on the device.

Future cloud/AI features must be explicit opt-in and designed so the user understands what leaves the device and why.

## Generate the Xcode project

```bash
brew install xcodegen
xcodegen generate
open ATHLTH.xcodeproj
```

Select your Apple ID's **Personal Team** under Signing & Capabilities and run on a physical iPhone.

## Roadmap

- **V0.1** — workouts, routes, sleep, heart, training choice, capability testing
- **V0.2** — splits, pace/HR charts, personal records, full strength logging
- **V0.3** — recovery and trends
- **V0.4** — Apple Watch + WorkoutKit planning
- **V0.5** — optional Home Assistant webhook integration
- **V0.6+** — privacy-aware ATHLTH Coach / AI

> ATHLTH is a working product name and has not yet been represented as a completed trademark clearance.
