import Foundation

/// Small, Codable public workout prescription for the paired iPhone's
/// private iPad live view. No GPS points or personal health samples.
struct ATHLTHWatchRunningStageSummary: Codable, Hashable {
    let index: Int
    let title: String
    let phase: String?
    let durationSeconds: TimeInterval?
    let distanceMeters: Double?
}
