import ActivityKit
import Foundation

struct ATHLTHWorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var elapsedTime: TimeInterval
        var distanceMeters: Double
        var heartRate: Double
        var updatedAt: Date
    }

    var workoutTitle: String
    var systemImage: String
    var startedAt: Date?
}
