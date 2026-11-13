import Foundation

/// Lightweight exercise timeline, derived only from the existing workout
/// engine. Raw GPS points, contacts and HealthKit samples are never relayed.
struct ATHLTHLiveWorkoutStage: Codable, Equatable, Identifiable {
    let index: Int
    let title: String
    let phase: String
    let durationSeconds: Double?
    let distanceMeters: Double?

    var id: Int { index }
}

struct ATHLTHLiveStrengthExercise: Codable, Equatable, Identifiable {
    let index: Int
    let name: String
    let completedSets: Int
    let totalSets: Int

    var id: Int { index }
}
