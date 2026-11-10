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
        var knownIDs = Set(health.map(\.id))
        // Group existing Health strength workouts into two-minute buckets.
        // This avoids re-sorting the entire Health history every time Home
        // observes a new HealthKit or local-strength store update.
        func bucket(for date: Date) -> Int {
            Int(floor(date.timeIntervalSince1970 / 120))
        }
        var healthStrengthByBucket: [Int: [WorkoutSummary]] = [:]
        for workout in health where workout.activity == .strength {
            healthStrengthByBucket[bucket(for: workout.startDate), default: []]
                .append(workout)
        }

        func hasMatchingHealth(start: Date, duration: TimeInterval) -> Bool {
            let index = bucket(for: start)
            // Adjacent buckets preserve the previous strict +/-120 second
            // start-time and duration window, including bucket boundaries.
            for near in (index - 1)...(index + 1) {
                guard let candidates = healthStrengthByBucket[near] else {
                    continue
                }
                if candidates.contains(where: {
                    abs($0.startDate.timeIntervalSince(start)) < 120 &&
                        abs($0.duration - duration) < 120
                }) {
                    return true
                }
            }
            return false
        }

        for local in localStrength {
            guard let ended = local.endedAt,
                  ended >= local.startedAt else { continue }

            let recordedID = local.healthMetrics.healthKitWorkoutUUID ?? local.id
            if knownIDs.contains(recordedID) || knownIDs.contains(local.id) {
                continue
            }

            let localDuration = ended.timeIntervalSince(local.startedAt)
            if hasMatchingHealth(start: local.startedAt, duration: localDuration) {
                continue
            }

            knownIDs.insert(recordedID)
            knownIDs.insert(local.id)
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
