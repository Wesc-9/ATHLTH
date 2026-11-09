import Foundation

/// A read-only Studio projection. ATHLTH strength workouts can be completed
/// locally before Apple Health has imported the same activity. Retain those
/// recordings without double-counting linked HealthKit sessions.
enum ATHLTHStudioRecordedWorkouts {
    static func merged(
        health: [WorkoutSummary],
        localStrength: [StrengthWorkoutLog]
    ) -> [WorkoutSummary] {
        var combined = health
        let healthIDs = Set(health.map(\.id))
        let knownIDs = Set(health.map(\.id))

        for local in localStrength {
            guard let ended = local.endedAt,
                  ended >= local.startedAt else { continue }

            let linkedID = local.healthMetrics.healthKitWorkoutUUID
            if let linkedID, healthIDs.contains(linkedID) { continue }
            if knownIDs.contains(local.id) { continue }

            let localDuration = ended.timeIntervalSince(local.startedAt)
            let foundMatchingHealth = health.contains {
                $0.activity == .strength &&
                abs($0.startDate.timeIntervalSince(local.startedAt)) < 120 &&
                abs($0.duration - localDuration) < 120
            }
            if foundMatchingHealth { continue }

            combined.append(WorkoutSummary(localStrengthWorkout: local))
        }
        return combined.sorted { $0.startDate > $1.startDate }
    }
}

extension WorkoutSummary {
    /// The underlying workout is kept in ATHLTH's account-scoped local store.
    /// Do not invent Health metrics that the user never recorded.
    init(localStrengthWorkout: StrengthWorkoutLog) {
        id = localStrengthWorkout.healthMetrics.healthKitWorkoutUUID
            ?? localStrengthWorkout.id
        activity = .strength
        startDate = localStrengthWorkout.startedAt
        endDate = localStrengthWorkout.endedAt ?? localStrengthWorkout.startedAt
        duration = max(0, endDate.timeIntervalSince(startDate))
        distanceMeters = nil
        activeEnergyKilocalories = localStrengthWorkout.healthMetrics.activeCalories
        isIndoor = nil
    }
}
