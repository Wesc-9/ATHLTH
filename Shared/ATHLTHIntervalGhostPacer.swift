import Foundation

/// Independent of GPS route Ghost Race: the target runner is restarted at the
/// beginning of every work repetition. Recovery/warmup/cooldown contribute
/// neither elapsed seconds nor meters and never change the comparison.
enum ATHLTHIntervalGhostPacer {

    /// A segment-aware virtual pacer. Callers provide one completed segment
    /// at a time, so the same calculation works for iPhone and Apple Watch.
    /// Work and recovery remain separate: resting never consumes work pace.
    enum SegmentKind {
        case warmup
        case work
        case passiveRecovery
        case activeRecovery
        case cooldown
    }

    enum RecoveryPolicy {
        case freeze
        case followActualDistance
        case targetPace(secondsPerKilometer: Double)
    }

    enum Scope {
        case wholeWorkout
        case mainOnly
    }

    struct VirtualProgress {
        var ghostMeters: Double = 0
        var runnerMeters: Double = 0

        var leadMeters: Double { runnerMeters - ghostMeters }
    }

    /// Returns nil rather than propagating NaN, negative elapsed time, or
    /// invalid pace into the live Ghost comparison.
    static func advance(
        _ progress: VirtualProgress,
        kind: SegmentKind,
        scope: Scope,
        elapsedSeconds: TimeInterval,
        actualMeters: Double,
        workPaceSecondsPerKilometer: Double,
        recovery: RecoveryPolicy
    ) -> VirtualProgress? {
        guard elapsedSeconds.isFinite, elapsedSeconds >= 0,
              actualMeters.isFinite, actualMeters >= 0,
              progress.ghostMeters.isFinite, progress.runnerMeters.isFinite,
              workPaceSecondsPerKilometer.isFinite,
              workPaceSecondsPerKilometer > 0
        else { return nil }

        let included: Bool
        switch scope {
        case .wholeWorkout: included = true
        case .mainOnly:
            included = kind == .work || kind == .activeRecovery ||
                kind == .passiveRecovery
        }
        guard included else { return progress }

        var next = progress
        switch kind {
        case .work, .warmup, .cooldown:
            next.ghostMeters += elapsedSeconds / workPaceSecondsPerKilometer * 1_000
            next.runnerMeters += actualMeters
        case .passiveRecovery:
            // Pause is excluded from both virtual timelines.
            break
        case .activeRecovery:
            switch recovery {
            case .freeze:
                break
            case .followActualDistance:
                next.ghostMeters += actualMeters
                next.runnerMeters += actualMeters
            case .targetPace(let secondsPerKilometer):
                guard secondsPerKilometer.isFinite,
                      secondsPerKilometer > 0 else { return nil }
                next.ghostMeters += elapsedSeconds / secondsPerKilometer * 1_000
                next.runnerMeters += actualMeters
            }
        }
        return next
    }

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
