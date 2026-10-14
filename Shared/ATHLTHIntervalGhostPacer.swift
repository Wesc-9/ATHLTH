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

    /// Recovery does not advance the virtual target at work pace. With
    /// follow enabled Ghost matches actual recovery progress, not a target
    /// distance. Threshold prevents misclassifying brief pace sensor spikes.
    static func followsRecovery(
        step: WatchRunningWorkoutStep,
        observedPaceSecondsPerKilometer: Double?
    ) -> Bool {
        guard step.phase == "recovery",
              step.ghostFollowsRecovery == true,
              let workPace = step.ghostPaceSecondsPerKilometer,
              workPace.isFinite, workPace > 0,
              let observedPaceSecondsPerKilometer,
              observedPaceSecondsPerKilometer.isFinite,
              observedPaceSecondsPerKilometer > 0 else { return false }
        let slowdown = Double(
            min(max(step.ghostRecoverySlowdownPercent ?? 25, 10), 60)
        ) / 100
        return observedPaceSecondsPerKilometer >= workPace / (1 - slowdown)
    }

    static func isGhostEnabled(_ step: WatchRunningWorkoutStep) -> Bool {
        (step.phase == "work" ||
         (step.phase == "recovery" && step.ghostFollowsRecovery == true)) &&
            (step.ghostPaceSecondsPerKilometer ?? 0) > 0
    }
}
