import Foundation

enum GarminHistoryMatchPolicy {
    /// Match only known sports. A candidate is a label, not permission to merge
    /// or erase a workout. Preserve the original source and both records.
    static func possibleMatch(_ garmin: WearableWorkoutRecord, _ local: SocialPublishableWorkout) -> Bool {
        guard garmin.provider == .garmin else { return false }
        let kind: WorkoutKind
        switch local.activity {
        case .running: kind = .running
        case .walking, .hiking: kind = .walking
        case .strength: kind = .strength
        case .yoga: kind = .mobility
        default: return false
        }
        let reference = WearableWorkoutRecord(
            id: local.id.uuidString, provider: .none, kind: kind,
            startedAt: local.startDate, endedAt: local.endDate, duration: local.duration,
            activeEnergyKilocalories: local.activeEnergyKilocalories,
            distanceMeters: local.distanceMeters, averageHeartRate: nil, maximumHeartRate: nil, route: nil
        )
        return GarminImportNormalizer.isPossibleDuplicate(garmin, reference)
    }
}
