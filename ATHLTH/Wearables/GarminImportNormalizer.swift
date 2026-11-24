import Foundation

/// Internal ATHLTH staging schema, NOT a Garmin API response schema.
/// A future approved transport maps its versioned response into this model.
/// Never store raw Garmin payloads or credentials in this schema.
struct GarminActivityInput: Codable, Equatable {
    let activityID: String
    let activityType: String
    let deviceModel: String?
    let startedAt: Date
    let elapsedSeconds: Double?
    let durationSeconds: Double
    let distanceMeters: Double?
    let activeEnergyKilocalories: Double?
    let averageHeartRate: Double?
    let maximumHeartRate: Double?
}

struct GarminImportedActivity: Equatable {
    let workout: WearableWorkoutRecord
    let originalActivityType: String
    let deviceModel: String?
}

enum GarminImportError: Error, Equatable {
    case accessNotApproved
    case invalidActivity
}

enum GarminImportNormalizer {
    static func activity(_ input: GarminActivityInput) throws -> GarminImportedActivity {
        let id = input.activityID.trimmingCharacters(in: .whitespacesAndNewlines)
        let elapsed = input.elapsedSeconds ?? input.durationSeconds
        guard !id.isEmpty, input.startedAt.timeIntervalSince1970.isFinite,
              input.durationSeconds.isFinite, input.durationSeconds > 0,
              elapsed.isFinite, elapsed >= input.durationSeconds,
              input.startedAt.addingTimeInterval(elapsed).timeIntervalSince1970.isFinite
        else { throw GarminImportError.invalidActivity }

        // Preserve unknown sports instead of silently classifying them as running.
        let type = input.activityType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let kind: WorkoutKind
        switch type {
        case "running", "trail_running", "treadmill_running", "track_running",
             "indoor_running", "virtual_running": kind = .running
        case "walking", "hiking", "casual_walking", "speed_walking": kind = .walking
        case "strength_training", "strength", "weight_training": kind = .strength
        case "yoga", "pilates", "flexibility": kind = .mobility
        case "meditation": kind = .recovery
        default: kind = .custom
        }
        let device = input.deviceModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GarminImportedActivity(
            workout: WearableWorkoutRecord(
                id: "garmin:" + id, provider: .garmin, kind: kind,
                startedAt: input.startedAt, endedAt: input.startedAt.addingTimeInterval(elapsed),
                duration: input.durationSeconds,
                activeEnergyKilocalories: nonnegative(input.activeEnergyKilocalories),
                distanceMeters: nonnegative(input.distanceMeters),
                averageHeartRate: positive(input.averageHeartRate),
                maximumHeartRate: positive(input.maximumHeartRate),
                route: nil
            ),
            originalActivityType: input.activityType,
            deviceModel: device?.isEmpty == true ? nil : device
        )
    }

    /// Repeat deliveries replace an earlier version of the same activity.
    /// Scope to one authorized account; never merge records across accounts.
    static func normalize(_ inputs: [GarminActivityInput]) throws -> [GarminImportedActivity] {
        var byID: [String: GarminImportedActivity] = [:]
        for input in inputs {
            let item = try activity(input)
            byID[item.workout.id] = item
        }
        return byID.values.sorted {
            if $0.workout.startedAt == $1.workout.startedAt {
                return $0.workout.id < $1.workout.id
            }
            return $0.workout.startedAt > $1.workout.startedAt
        }
    }

    /// A potential cross-source duplicate is review evidence only.
    /// Do not silently delete or combine Apple Health and Garmin activities.
    static func isPossibleDuplicate(
        _ garmin: WearableWorkoutRecord, _ other: WearableWorkoutRecord
    ) -> Bool {
        guard garmin.provider == .garmin, other.provider != .garmin,
              garmin.kind != .custom, garmin.kind == other.kind,
              abs(garmin.startedAt.timeIntervalSince(other.startedAt)) <= 60,
              abs(garmin.duration - other.duration) <= 90
        else { return false }
        if let a = garmin.distanceMeters, let b = other.distanceMeters {
            return abs(a - b) <= max(100, max(a, b) * 0.05)
        }
        return true
    }

    private static func nonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value = nonnegative(value), value > 0 else { return nil }
        return value
    }
}

/// Production placeholder is deliberately fail-closed. The Personal API is
/// not a commercial authentication route. No user data is fetched, persisted,
/// exported or forwarded to Coach until approved Business access is wired.
struct GarminDataSource: WearableDataSource {
    let provider: TrainingDeviceProvider = .garmin
    var capabilities: Set<WearableDataCapability> { [] }
    var isAuthorized: Bool { false }

    func refreshDailySnapshot() async throws -> WearableDailySnapshot? {
        throw GarminImportError.accessNotApproved
    }

    func refreshWorkouts(since date: Date) async throws -> [WearableWorkoutRecord] {
        throw GarminImportError.accessNotApproved
    }

    func refreshProgressSnapshot(
        startDate: Date, endDate: Date, previousStartDate: Date,
        previousEndDate: Date, grouping: HealthProgressGrouping
    ) async throws -> HealthProgressSnapshot? {
        throw GarminImportError.accessNotApproved
    }

    func refreshPersonalRecords() async throws -> [HealthPersonalRecord] {
        throw GarminImportError.accessNotApproved
    }
}
