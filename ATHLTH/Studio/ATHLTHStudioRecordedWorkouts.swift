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
        // Sort the matching activity once. Binary search limits each local
        // strength log to nearby HealthKit start times instead of scanning the
        // entire Health history on every Home render.
        let healthStrength = health.filter { $0.activity == .strength }
            .sorted { $0.startDate < $1.startDate }

        func hasMatchingHealth(start: Date, duration: TimeInterval) -> Bool {
            let lowerBound = start.addingTimeInterval(-120)
            let upperBound = start.addingTimeInterval(120)
            var low = 0
            var high = healthStrength.count
            while low < high {
                let mid = low + (high - low) / 2
                if healthStrength[mid].startDate <= lowerBound {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            while low < healthStrength.count {
                let candidate = healthStrength[low]
                if candidate.startDate >= upperBound { break }
                if abs(candidate.duration - duration) < 120 { return true }
                low += 1
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
