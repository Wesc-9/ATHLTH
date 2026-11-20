import Foundation

/// Shared preflight guard before appending intervals to a live iPhone/Watch run.
/// When free running, both "start now" and "queue for manual start"
/// are valid. An active structured block cannot be replaced, only queued.
enum ATHLTHRunningWorkoutAppendPolicy {
    /// Free running already counts toward total time and distance. Do not
    /// insert the template's suggested warm-up as a second workout phase.
    static func stepsAfterExistingFreeRun(
        _ steps: [WatchRunningWorkoutStep]
    ) -> [WatchRunningWorkoutStep] {
        Array(steps.drop(while: { $0.phase == "warmup" }))
    }

    /// One explicit, unbounded free segment; only the original recorder
    /// supplies elapsed seconds/meters. No new HealthKit session or timer.
    static func freeRunningStage() -> WatchRunningWorkoutStep {
        WatchRunningWorkoutStep(
            id: UUID(),
            title: ATHLTHLocalization.choose(
                english: "Free running", norwegian: "Fri løping"
            ),
            measure: .open,
            distanceMeters: nil,
            durationSeconds: nil,
            intensityText: nil,
            phase: "free"
        )
    }

    static func canAppend(
        hasInProgressStructuredSteps: Bool,
        startNow: Bool,
        steps: [WatchRunningWorkoutStep]
    ) -> Bool {
        guard !steps.isEmpty, steps.count <= 150 else { return false }

        guard steps.allSatisfy({ step in
            switch step.measure {
            case .time:
                return step.durationSeconds.map {
                    $0.isFinite && (15...7_200).contains($0)
                } == true
            case .distance:
                return step.distanceMeters.map {
                    $0.isFinite && (10...100_000).contains($0)
                } == true
            case .open:
                return true
            }
        }) else { return false }

        // Free running has no active structured block: selecting intervals
        // must be allowed to queue an OPEN phase until the user taps Next.
        // An existing structured workout may only accept queued additions.
        return !hasInProgressStructuredSteps || !startNow
    }
}
