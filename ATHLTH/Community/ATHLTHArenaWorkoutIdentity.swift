import Foundation

/// Avoid displaying the same real-life workout twice when iPhone/Watch and
/// HealthKit history contain different identifiers for its mirrored copies.
/// This is a conservative on-device guard, not server source attestation.
enum ATHLTHArenaWorkoutIdentity {
    static func samePhysicalWorkout(
        _ lhs: SocialPublishableWorkout,
        _ rhs: SocialPublishableWorkout
    ) -> Bool {
        if lhs.id == rhs.id { return true }
        guard lhs.activity == rhs.activity,
              abs(lhs.startDate.timeIntervalSince(rhs.startDate)) <= 90,
              abs(lhs.endDate.timeIntervalSince(rhs.endDate)) <= 90 else {
            return false
        }
        return comparableDistances(lhs.distanceMeters, rhs.distanceMeters)
    }

    static func alreadyShared(
        _ workout: SocialPublishableWorkout,
        entries: [ATHLTHArenaWorkoutEvidence],
        userID: UUID
    ) -> Bool {
        entries.contains { entry in
            guard entry.userID == userID else { return false }
            if entry.sourceWorkoutID == workout.id { return true }
            guard entry.activityType == activityValue(workout.activity),
                  abs(entry.startedAt.timeIntervalSince(workout.startDate)) <= 90,
                  abs(entry.endedAt.timeIntervalSince(workout.endDate)) <= 90 else {
                return false
            }
            return comparableDistances(
                entry.reportedDistanceMeters,
                workout.distanceMeters
            )
        }
    }

    static func distinct(
        _ workouts: [SocialPublishableWorkout]
    ) -> [SocialPublishableWorkout] {
        var result: [SocialPublishableWorkout] = []
        for workout in workouts {
            if result.contains(where: { samePhysicalWorkout($0, workout) }) {
                continue
            }
            result.append(workout)
        }
        return result
    }

    private static func comparableDistances(
        _ lhs: Double?, _ rhs: Double?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (let a?, let b?):
            guard a.isFinite, b.isFinite, a >= 0, b >= 0 else {
                return false
            }
            return abs(a - b) <= max(100, max(a, b) * 0.03)
        default:
            return false
        }
    }

    private static func activityValue(_ activity: WorkoutActivity) -> String {
        switch activity {
        case .running: return "running"
        case .walking: return "walking"
        case .strength: return "strength"
        default: return "other"
        }
    }
}
