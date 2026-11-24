import Foundation

enum GarminHistoryMatchPolicy {
    static func activity(for item: GarminImportedActivity) -> WorkoutActivity {
        let type = item.originalActivityType.lowercased()
        if type.contains("cycling") || type.contains("biking") { return .cycling }
        if type.contains("swim") { return .swimming }
        if type == "hiking" { return .hiking }
        if type == "yoga" { return .yoga }
        if type.contains("rowing") { return .rowing }
        switch item.workout.kind {
        case .running: return .running
        case .walking: return .walking
        case .strength: return .strength
        default: return .other
        }
    }

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

enum GarminUnifiedHistoryRow: Identifiable {
    case local(SocialPublishableWorkout)
    case garmin(GarminImportedActivity, possibleDuplicate: Bool)

    var id: String {
        switch self {
        case .local(let workout): return "local:" + workout.id.uuidString
        case .garmin(let activity, _): return activity.workout.id
        }
    }
    var date: Date {
        switch self {
        case .local(let workout): return workout.startDate
        case .garmin(let activity, _): return activity.workout.startedAt
        }
    }

    /// Do not drop a possible duplicate without a verified cross-source ID.
    /// These read-only rows never enter training totals or social publishing.
    static func merge(local: [SocialPublishableWorkout], garmin: [GarminImportedActivity]) -> [Self] {
        let rows = local.map { Self.local($0) } + garmin.map { item in
            Self.garmin(item, possibleDuplicate: local.contains {
                GarminHistoryMatchPolicy.possibleMatch(item.workout, $0)
            })
        }
        return rows.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}
