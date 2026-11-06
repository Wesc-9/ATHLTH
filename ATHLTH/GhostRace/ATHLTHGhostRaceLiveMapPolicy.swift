import Foundation

/// Presentation-only safety gate. The racing engine has already map-matched
/// the GPS; these checks prevent stale/paused positions from looking live.
enum ATHLTHGhostRaceLiveMapPolicy {
    static func acceptedComparison(
        _ comparison: GhostRaceComparison?,
        paused: Bool,
        at date: Date
    ) -> GhostRaceComparison? {
        guard !paused, let comparison,
              comparison.updatedAt <= date.addingTimeInterval(5),
              comparison.updatedAt >= date.addingTimeInterval(-18),
              comparison.signedDistanceMeters.isFinite,
              comparison.signedTimeSeconds.isFinite,
              comparison.routeDeviationMeters.isFinite,
              comparison.userProgress.isFinite,
              comparison.ghostProgress.isFinite,
              (0...1).contains(comparison.userProgress),
              (0...1).contains(comparison.ghostProgress),
              (-90...90).contains(comparison.userLatitude),
              (-180...180).contains(comparison.userLongitude),
              (-90...90).contains(comparison.ghostLatitude),
              (-180...180).contains(comparison.ghostLongitude)
        else { return nil }
        return comparison
    }
}
