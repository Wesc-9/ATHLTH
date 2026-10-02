import Foundation

enum WearableDataCapability: String, CaseIterable, Codable, Hashable {
    case workouts
    case heartRate
    case restingHeartRate
    case hrv
    case sleep
    case steps
    case activeEnergy
    case exerciseMinutes
    case distance
    case route
}

struct WearableWorkoutRecord: Identifiable, Codable, Hashable {
    let id: String
    let provider: TrainingDeviceProvider
    let kind: WorkoutKind
    let startedAt: Date
    let endedAt: Date?
    let duration: TimeInterval
    let activeEnergyKilocalories: Double?
    let distanceMeters: Double?
    let averageHeartRate: Double?
    let maximumHeartRate: Double?
    let route: [RouteCoordinate]?
}

struct WearableDailySnapshot {
    let provider: TrainingDeviceProvider
    let capturedAt: Date
    let training: TrainingHealthSummary
    let sleep: SleepSummary
    let heart: HeartSummary
}

protocol WearableDataSource {
    var provider: TrainingDeviceProvider { get }
    var capabilities: Set<WearableDataCapability> { get }
    var isAuthorized: Bool { get }

    // The Garmin adapter must populate the same core models already consumed
    // by Home and Recovery so provider-specific data never leaks into UI code.
    func refreshDailySnapshot() async throws -> WearableDailySnapshot?

    // Historical data powers workout history, Progress and PR detection.
    func refreshWorkouts(
        since date: Date
    ) async throws -> [WearableWorkoutRecord]

    func refreshProgressSnapshot(
        startDate: Date,
        endDate: Date,
        previousStartDate: Date,
        previousEndDate: Date,
        grouping: HealthProgressGrouping
    ) async throws -> HealthProgressSnapshot?

    func refreshPersonalRecords() async throws -> [HealthPersonalRecord]
}

enum GarminIntegrationState: String, Codable, Hashable {
    case awaitingDeveloperAccess
    case readyForAuthorization
    case connected
    case unavailable

    var title: String {
        switch self {
        case .awaitingDeveloperAccess:
            return "Awaiting Garmin access"
        case .readyForAuthorization:
            return "Ready to connect"
        case .connected:
            return "Connected"
        case .unavailable:
            return "Unavailable"
        }
    }
}

enum GarminDataContract {
    static let targetCapabilities: Set<WearableDataCapability> = [
        .workouts,
        .heartRate,
        .restingHeartRate,
        .hrv,
        .sleep,
        .steps,
        .activeEnergy,
        .exerciseMinutes,
        .distance,
        .route
    ]

    static let state: GarminIntegrationState = .awaitingDeveloperAccess
}
