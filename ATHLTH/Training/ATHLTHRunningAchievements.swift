import Foundation

/// Evidence-backed personal achievements for one completed running workout.
/// Values are recorded, not a planned target or an estimate from average pace.
struct ATHLTHRunningAchievement: Identifiable, Equatable {
    enum Kind: String {
        case fastestKilometer
        case fastestFiveKilometers
        case longestRun
        case routePersonalBest
        case maximumRecordedHeartRate
    }

    let kind: Kind
    let value: Double
    let previousValue: Double
    var routeTitle: String? = nil

    var id: String { kind.rawValue }
}

/// Only compare with *earlier* completed, verified results. A first attempt
/// with no previous measurement is not misrepresented as a personal record.
enum ATHLTHRunningAchievementPolicy {
    static func fasterTime(
        kind: ATHLTHRunningAchievement.Kind,
        current: Double?,
        previousBest: Double?,
        allowedRange: ClosedRange<Double>
    ) -> ATHLTHRunningAchievement? {
        guard let current, let previousBest,
              current.isFinite, previousBest.isFinite,
              allowedRange.contains(current),
              allowedRange.contains(previousBest),
              previousBest - current >= 1
        else { return nil }

        return ATHLTHRunningAchievement(
            kind: kind, value: current, previousValue: previousBest
        )
    }

    static func longestRun(
        currentMeters: Double?,
        previousBestMeters: Double?
    ) -> ATHLTHRunningAchievement? {
        guard let currentMeters, let previousBestMeters,
              currentMeters.isFinite, previousBestMeters.isFinite,
              currentMeters >= 1_000, previousBestMeters >= 1_000,
              currentMeters - previousBestMeters >= 20
        else { return nil }

        return ATHLTHRunningAchievement(
            kind: .longestRun, value: currentMeters,
            previousValue: previousBestMeters
        )
    }

    /// A maximum HR is informational, not a score or a fitness achievement.
    /// With no trustworthy comparison from previous sessions, show nothing.
    static func maximumHeartRate(
        currentBPM: Double?,
        previousMaximumBPM: Double?
    ) -> ATHLTHRunningAchievement? {
        guard let currentBPM, let previousMaximumBPM,
              currentBPM.isFinite, previousMaximumBPM.isFinite,
              (40...240).contains(currentBPM),
              (40...240).contains(previousMaximumBPM),
              currentBPM - previousMaximumBPM >= 2
        else { return nil }

        return ATHLTHRunningAchievement(
            kind: .maximumRecordedHeartRate,
            value: currentBPM, previousValue: previousMaximumBPM
        )
    }

    static func routePersonalBest(
        current: RouteAttemptRecord?,
        attempts: [RouteAttemptRecord],
        userID: UUID,
        workoutID: UUID,
        routeName: String?
    ) -> ATHLTHRunningAchievement? {
        guard let current,
              current.userID == userID,
              current.workoutID == workoutID,
              current.activityType.lowercased() == "running",
              current.leaderboardEligible,
              current.durationSeconds.isFinite,
              current.durationSeconds >= 30
        else { return nil }

        let older = attempts.filter {
            $0.id != current.id &&
            $0.workoutID != current.workoutID &&
            $0.routeID == current.routeID &&
            $0.userID == userID &&
            $0.activityType.lowercased() == "running" &&
            $0.leaderboardEligible &&
            $0.startedAt < current.startedAt &&
            $0.durationSeconds.isFinite &&
            $0.durationSeconds >= 30
        }

        return fasterTime(
            kind: .routePersonalBest,
            current: current.durationSeconds,
            previousBest: older.map(\.durationSeconds).min(),
            allowedRange: 30...172_800
        ).map {
            ATHLTHRunningAchievement(
                kind: $0.kind,
                value: $0.value,
                previousValue: $0.previousValue,
                routeTitle: routeName
            )
        }
    }

    /// Preserve display priority, with the route record first when present,
    /// and a neutral heart-rate measurement last.
    static func top(
        _ achievements: [ATHLTHRunningAchievement],
        limit: Int = 3
    ) -> [ATHLTHRunningAchievement] {
        let order: [ATHLTHRunningAchievement.Kind] = [
            .routePersonalBest, .fastestKilometer,
            .fastestFiveKilometers, .longestRun,
            .maximumRecordedHeartRate
        ]
        return Array(achievements.sorted {
            (order.firstIndex(of: $0.kind) ?? order.count) <
            (order.firstIndex(of: $1.kind) ?? order.count)
        }.prefix(max(0, limit)))
    }
}
