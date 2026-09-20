import Foundation

struct WatchRoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var sequence: Int
}

struct WatchRouteTransfer: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var distanceKilometers: Double
    var elevationGainMeters: Double?
    var points: [WatchRoutePoint]
    var updatedAt: Date
}

enum WatchWorkoutKind: String, Codable, CaseIterable, Hashable {
    case running
    case walking
    case strength

    var title: String {
        switch self {
        case .running: return "Run"
        case .walking: return "Walk"
        case .strength: return "Strength"
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .strength: return "dumbbell.fill"
        }
    }
}

struct WatchWorkoutResult: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: WatchWorkoutKind
    var healthKitWorkoutUUID: UUID?
    var startedAt: Date
    var endedAt: Date
    var duration: TimeInterval
    var activeCalories: Double
    var distanceMeters: Double
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var routePointCount: Int
}

enum WatchWorkoutMirrorState: String, Codable, Hashable {
    case preparing
    case running
    case paused
    case ending
    case completed
    case failed
}

struct WatchWorkoutLiveSnapshot: Codable, Hashable {
    var kind: WatchWorkoutKind
    var state: WatchWorkoutMirrorState
    var startedAt: Date?
    var capturedAt: Date
    var elapsedTime: TimeInterval
    var heartRate: Double
    var activeCalories: Double
    var distanceMeters: Double
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var routePointCount: Int
}

struct WatchWorkoutMirrorCommand: Codable, Hashable {
    var command: WatchWorkoutCommand
}

enum WatchWorkoutCommand: String, Codable, Hashable {
    case end
    case pause
    case resume
}

enum WatchTransferKind: String {
    case route
    case workoutResult
    case workoutCommand
    case connectionPing
}

enum WatchTransferMetadataKey {
    static let kind = "kind"
    static let routeID = "routeID"
    static let title = "title"
    static let payload = "payload"
    static let command = "command"
    static let status = "status"
}
