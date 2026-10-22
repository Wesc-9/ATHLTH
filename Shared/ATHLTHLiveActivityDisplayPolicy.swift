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
    case cycling
    case elapsed
}

enum ATHLTHCompactIslandMetric: Equatable {
    case paused
    case strengthRest
    case strengthTimedSet
    case runningInterval
    case pace
    case distance
    case elapsed
}

enum ATHLTHLiveActivityDisplayPolicy {
    static func resolve(
        kindRaw: String?,
        phase: String,
        hasStrengthExercise: Bool,
        restEndsAt: Date?,
        hasTimedSetCountdown: Bool,
        hasRunningStep: Bool,
        recordedDistanceMeters: Double? = nil
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
        case "cycling":
            if let meters = recordedDistanceMeters,
               meters.isFinite, meters > 0 {
                return .cycling
            }
            return .elapsed
        default: return .elapsed
        }
    }

    /// The Live Activity represents the ATHLTH brand while starting or
    /// finishing. While training or paused, its icon identifies the sport.
    /// iOS itself controls the Island when no Live Activity is running.
    static func showsBrandMark(phase: String) -> Bool {
        phase != "running" && phase != "paused"
    }

    /// Choose one glanceable metric; details belong in the expanded Island.
    /// Strength defaults to elapsed workout time, never reps in the pill.
    static func compactMetric(
        focus: ATHLTHLiveActivityDisplayFocus,
        pace: TimeInterval? = nil,
        distanceMeters: Double? = nil
    ) -> ATHLTHCompactIslandMetric {
        switch focus {
        case .paused: return .paused
        case .strengthRest: return .strengthRest
        case .strengthTimedSet: return .strengthTimedSet
        case .strengthSet, .elapsed: return .elapsed
        case .runningInterval: return .runningInterval
        case .running:
            if let pace, pace.isFinite, pace >= 120, pace <= 1_800 {
                return .pace
            }
            return .elapsed
        case .walking, .cycling:
            if let meters = distanceMeters, meters.isFinite, meters > 0 {
                return .distance
            }
            return .elapsed
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

    /// Compact Island values must remain short when Now Playing is active
    /// alongside the workout Live Activity.
    static func compactRepetitions(_ reps: Int?) -> String {
        guard let reps, reps >= 0 else { return "—" }
        return "\(reps)×"
    }

    static func compactDistance(_ meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else { return "—" }
        if meters < 1_000 {
            return "\(Int(meters.rounded()))m"
        }
        return String(format: "%.1fk", meters / 1_000)
    }

    static func compactDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0,
              seconds < Double(Int.max) else { return "—" }
        let total = Int(seconds)
        if total >= 3_600 {
            return String(format: "%dh%02d", total / 3_600,
                          (total % 3_600) / 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
