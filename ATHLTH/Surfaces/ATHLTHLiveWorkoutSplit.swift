import Foundation

/// Completed interval/lap evidence from the recording engine. A split is
/// recorded, not estimated or reconstructed from today's wall clock.
struct ATHLTHLiveWorkoutSplit: Codable, Equatable, Identifiable {
    let index: Int
    let title: String
    let activeSeconds: Double
    let distanceMeters: Double
    var id: Int { index }
}
