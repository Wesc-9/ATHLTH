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
    /// Compact views prefer the existing local workout for a possible match.
    /// The full history retains both records for review; no source is deleted.
    static func unmatchedForDisplay(_ activities: [GarminImportedActivity],
                                    local: [SocialPublishableWorkout]) -> [GarminImportedActivity] {
        activities.filter { item in
            !local.contains { possibleMatch(item.workout, $0) }
        }
    }

    static func possibleMatch(_ garmin: WearableWorkoutRecord, _ local: SocialPublishableWorkout) -> Bool {
        possibleMatch(garmin, id: local.id, activity: local.activity, start: local.startDate,
                      end: local.endDate, duration: local.duration, distance: local.distanceMeters)
    }

    static func possibleMatch(_ garmin: WearableWorkoutRecord, summary: WorkoutSummary) -> Bool {
        possibleMatch(garmin, id: summary.id, activity: summary.activity, start: summary.startDate,
                      end: summary.endDate, duration: summary.duration, distance: summary.distanceMeters)
    }

    private static func possibleMatch(_ garmin: WearableWorkoutRecord, id: UUID,
                                      activity: WorkoutActivity, start: Date, end: Date,
                                      duration: TimeInterval, distance: Double?) -> Bool {
        guard garmin.provider == .garmin else { return false }
        let kind: WorkoutKind
        switch activity {
        case .running: kind = .running
        case .walking, .hiking: kind = .walking
        case .strength: kind = .strength
        case .yoga: kind = .mobility
        default: return false
        }
        let reference = WearableWorkoutRecord(
            id: id.uuidString, provider: .none, kind: kind,
            startedAt: start, endedAt: end, duration: duration,
            activeEnergyKilocalories: nil,
            distanceMeters: distance, averageHeartRate: nil, maximumHeartRate: nil, route: nil
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


/// A reconciliation ledger for the private preview only. One Garmin record
/// can be linked to one reviewed Apple Health record; no original is erased.
/// The caller must present the two original records and receive confirmation.
struct GarminReviewedWorkoutLinks {
    private(set) var links: [String: UUID] = [:]

    mutating func confirm(garminID: String, healthID: UUID, candidates: Set<UUID>) -> Bool {
        guard garminID.hasPrefix("garmin:"), candidates.contains(healthID),
              links[garminID] == nil, !links.values.contains(healthID) else { return false }
        links[garminID] = healthID
        return true
    }

    mutating func undo(garminID: String) {
        links.removeValue(forKey: garminID)
    }

    func confirmedMatch(garminID: String, candidates: Set<UUID>) -> UUID? {
        guard let id = links[garminID], candidates.contains(id) else { return nil }
        return id
    }
}
