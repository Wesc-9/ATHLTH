import Foundation

/// Small, deterministic Live Activity hierarchy shared by the iPhone and
/// widget extension. Never owns workout recording or changes a running set.
enum ATHLTHLiveActivityDisplayFocus: Equatable {
    case paused
    case strengthRest
    case strengthTimedSet
    case strengthSet
    case runningInterval
    case running
    case walking
    case elapsed
}

enum ATHLTHLiveActivityDisplayPolicy {
    static func resolve(
        kindRaw: String?,
        phase: String,
        hasStrengthExercise: Bool,
        restEndsAt: Date?,
        hasTimedSetCountdown: Bool,
        hasRunningStep: Bool
    ) -> ATHLTHLiveActivityDisplayFocus {
        if phase == "paused" { return .paused }

        if kindRaw == "strength" || hasStrengthExercise {
            if restEndsAt != nil { return .strengthRest }
            if hasTimedSetCountdown { return .strengthTimedSet }
            return .strengthSet
        }

        if (kindRaw == "running" || kindRaw == "walking") &&
            hasRunningStep {
            return .runningInterval
        }

        switch kindRaw {
        case "running": return .running
        case "walking": return .walking
        default: return .elapsed
        }
    }

    static func safeProgress(_ fraction: Double?) -> Double? {
        guard let fraction, fraction.isFinite else { return nil }
        return min(max(fraction, 0), 1)
    }

    /// Snapshot age limits only *claims of live data*; the existing workout
    /// continues independently of the Lock Screen and Dynamic Island.
    static func isRecent(
        updatedAt: Date,
        now: Date = Date(),
        limit: TimeInterval = 25
    ) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        return age.isFinite && age >= -5 && age <= limit
    }

    static func remainingTimedSet(
        secondsAtSnapshot: TimeInterval?,
        resumedAt: Date?,
        now: Date = Date()
    ) -> TimeInterval? {
        guard let secondsAtSnapshot,
              secondsAtSnapshot.isFinite,
              secondsAtSnapshot >= 0 else { return nil }
        let elapsed: TimeInterval
        if let resumedAt {
            elapsed = max(now.timeIntervalSince(resumedAt), 0)
        } else {
            elapsed = 0
        }
        return max(secondsAtSnapshot - elapsed, 0)
    }
}
