import Foundation

/// Independent of GPS route Ghost Race: the target runner is restarted at the
/// beginning of every work repetition. Recovery/warmup/cooldown contribute
/// neither elapsed seconds nor meters and never change the comparison.
enum ATHLTHIntervalGhostPacer {
    static func leadMeters(
        step: WatchRunningWorkoutStep,
        elapsedSeconds: TimeInterval,
        distanceMeters: Double
    ) -> Double? {
        guard step.phase == "work",
              let secondsPerKilometer = step.ghostPaceSecondsPerKilometer,
              secondsPerKilometer.isFinite, secondsPerKilometer > 0,
              elapsedSeconds.isFinite, elapsedSeconds >= 0,
              distanceMeters.isFinite, distanceMeters >= 0
        else { return nil }
        let expectedMeters = elapsedSeconds / secondsPerKilometer * 1_000
        return distanceMeters - expectedMeters
    }

    static func isGhostEnabled(_ step: WatchRunningWorkoutStep) -> Bool {
        step.phase == "work" &&
            (step.ghostPaceSecondsPerKilometer ?? 0) > 0
    }
}
