# ATHLTH V0.1 — Free Apple Personal Team testing

This is the preferred path for the first ATHLTH device tests.

## What this path is for

Use a free Apple ID / Personal Team to install ATHLTH directly from Xcode onto your own iPhone.

For V0.1 we care about proving:

- Apple Health authorization
- workouts
- running/walking GPS routes
- sleep
- heart rate / resting heart rate / HRV
- strength training selection
- whether background delivery can be enabled with the current signing profile
- whether WorkoutKit is available in the build

The temporary **Lab** tab in ATHLTH exposes these checks.

## On the borrowed Mac

1. Install the newest Xcode the Mac supports.
2. Sign in to Xcode with your Apple ID:
   **Xcode → Settings → Accounts**.
3. Clone `Wesc-9/ATHLTH`.
4. Install XcodeGen:

   ```bash
   brew install xcodegen
   ```

5. In Terminal, inside the ATHLTH folder:

   ```bash
   xcodegen generate
   open ATHLTH.xcodeproj
   ```

6. In Xcode select the **ATHLTH** target → **Signing & Capabilities**.
7. Turn on **Automatically manage signing**.
8. Select your **Personal Team**.
9. Connect the iPhone to the Mac and select it as the run destination.
10. If iOS asks for **Developer Mode**, enable it and restart the iPhone when prompted.
11. Press **Run** in Xcode.

## First launch

ATHLTH should show the Apple Health permission screen.

Allow the data you want to test, especially:

- Workouts
- Workout Routes
- Heart Rate
- Resting Heart Rate
- Heart Rate Variability
- Sleep
- Active Energy
- Walking + Running Distance

Then open the **Lab** tab.

## Lab test order

1. **Health authorization** — check that the request is no longer required.
2. **Workout GPS route** — use a recent outdoor run/walk recorded with route data.
3. **Background delivery** — run the test and copy the exact result.
4. Confirm **WorkoutKit framework** is shown as available.

A background-delivery error in this first build is expected because the dedicated background-delivery entitlement is intentionally not included yet. Once the base Personal Team build works, we can enable that entitlement in a separate commit and test whether signing accepts it.

## Personal Team limitation

Free development provisioning is temporary, so the app must periodically be rebuilt/re-signed from Xcode. This is fine for early V0.x development; TestFlight can be enabled later without rewriting the app.
