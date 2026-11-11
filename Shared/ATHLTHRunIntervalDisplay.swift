import Foundation

/// Always present structured timed-step countdowns in hours:minutes:seconds.
/// Ceil keeps a positive remaining fraction from being shown as zero.
enum ATHLTHRunStepCountdown {
    static func display(_ seconds: TimeInterval) -> String {
        let bounded = seconds.isFinite ? max(0, min(seconds, 359_999)) : 0
        let count = Int(ceil(bounded))
        return String(format: "%02d:%02d:%02d",
                      count / 3600, (count / 60) % 60, count % 60)
    }
}

/// UI-only run interval metrics. Countdown is derived from the Watch workout
/// engine's current-step elapsed time or distance, never a second timer.
enum ATHLTHRunIntervalRemainingUnit: Equatable {
    case seconds
    case meters
    case open
}

struct ATHLTHRunIntervalReadout: Equatable {
    var unit: ATHLTHRunIntervalRemainingUnit
    var remaining: Double?
    var progress: Double?

    static func resolve(
        step: WatchRunningWorkoutStep,
        elapsedSeconds: TimeInterval,
        distanceMeters: Double
    ) -> Self {
        switch step.measure {
        case .time:
            guard let target = step.durationSeconds,
                  target.isFinite, target > 0
            else {
                return .init(unit: .seconds, remaining: nil, progress: nil)
            }
            let current = elapsedSeconds.isFinite
                ? max(elapsedSeconds, 0) : 0
            return .init(
                unit: .seconds,
                remaining: max(target - current, 0),
                progress: min(current / target, 1)
            )

        case .distance:
            guard let target = step.distanceMeters,
                  target.isFinite, target > 0
            else {
                return .init(unit: .meters, remaining: nil, progress: nil)
            }
            let current = distanceMeters.isFinite
                ? max(distanceMeters, 0) : 0
            return .init(
                unit: .meters,
                remaining: max(target - current, 0),
                progress: min(current / target, 1)
            )

        case .open:
            return .init(unit: .open, remaining: nil, progress: nil)
        }
    }
}

/// A target is actionable only with valid bounds and a measured heart rate.
/// Without a fresh value the screen must say "waiting", not "within zone".
enum ATHLTHRunPulseTargetStatus: Equatable {
    case unavailable
    case waiting
    case below
    case within
    case above

    static func resolve(
        heartRate: Double?,
        minimum: Double?,
        maximum: Double?
    ) -> Self {
        guard let minimum, let maximum,
              minimum.isFinite, maximum.isFinite,
              minimum > 0, maximum >= minimum
        else { return .unavailable }

        guard let heartRate, heartRate.isFinite, heartRate > 0
        else { return .waiting }

        if heartRate < minimum { return .below }
        if heartRate > maximum { return .above }
        return .within
    }
}


/// A stable interval numerator/denominator derived from the authoritative
/// expanded workout steps. Warm-up, cooldown, free run and recovery do not
/// inflate a 4×4 workout into "step 1 of 9".
struct ATHLTHRunningIntervalPosition: Equatable {
    let ordinal: Int
    let total: Int
    let isRecovery: Bool

    var nextOrdinal: Int {
        isRecovery ? min(ordinal + 1, total) : ordinal
    }

    static func resolve(
        steps: [WatchRunningWorkoutStep],
        currentIndex: Int
    ) -> ATHLTHRunningIntervalPosition? {
        guard steps.indices.contains(currentIndex) else { return nil }

        func isEffort(_ step: WatchRunningWorkoutStep) -> Bool {
            (step.phase == "work" || step.phase == "interval") &&
            step.measure != .open
        }
        let total = steps.filter(isEffort).count
        guard total > 1 else { return nil }
        let completedBefore = steps.prefix(currentIndex).filter(isEffort).count
        let current = steps[currentIndex]
        if isEffort(current) {
            return .init(
                ordinal: min(completedBefore + 1, total),
                total: total,
                isRecovery: false
            )
        }
        if current.phase == "recovery" || current.phase == "rest" {
            return .init(
                ordinal: min(max(completedBefore, 1), total),
                total: total,
                isRecovery: true
            )
        }
        return nil
    }
}
