import Foundation

struct ATHLTHSurfaceSnapshot: Codable, Equatable {
    var recoveryScore: Int?
    var recoveryState: String
    var nextWorkoutTitle: String?
    var nextWorkoutDate: Date?
    var primaryGoalTitle: String?
    var primaryGoalProgress: Double?
    var activeWorkout: ATHLTHSurfaceWorkoutSnapshot?
    var updatedAt: Date

    static let empty = ATHLTHSurfaceSnapshot(
        recoveryScore: nil,
        recoveryState: "Open ATHLTH",
        nextWorkoutTitle: nil,
        nextWorkoutDate: nil,
        primaryGoalTitle: nil,
        primaryGoalProgress: nil,
        activeWorkout: nil,
        updatedAt: .distantPast
    )
}

struct ATHLTHSurfaceWorkoutSnapshot: Codable, Equatable {
    var title: String
    var systemImage: String
    var state: String
    var startedAt: Date?
    var elapsedTime: TimeInterval
    var distanceMeters: Double
    var heartRate: Double
    var updatedAt: Date
}

enum ATHLTHSurfaceSharedStore {
    static let appGroupIdentifier = "group.com.wesc9.athlth"
    static let snapshotKey = "athlth.surface.snapshot.v1"

    static func load() -> ATHLTHSurfaceSnapshot {
        guard let defaults = UserDefaults(
            suiteName: appGroupIdentifier
        ),
        let data = defaults.data(forKey: snapshotKey),
        let decoded = try? JSONDecoder().decode(
            ATHLTHSurfaceSnapshot.self,
            from: data
        ) else {
            return .empty
        }

        return decoded
    }

    static func save(_ snapshot: ATHLTHSurfaceSnapshot) {
        guard let defaults = UserDefaults(
            suiteName: appGroupIdentifier
        ),
        let data = try? JSONEncoder().encode(snapshot)
        else {
            return
        }

        defaults.set(data, forKey: snapshotKey)
    }
}
