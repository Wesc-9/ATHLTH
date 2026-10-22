import Foundation

/// Shared preflight guard before appending intervals to a live iPhone/Watch run.
/// A new program may start only if the previous structured program is absent
/// or complete. Queue is available only behind an unfinished program.
enum ATHLTHRunningWorkoutAppendPolicy {
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

        return startNow
            ? !hasInProgressStructuredSteps
            : hasInProgressStructuredSteps
    }
}
