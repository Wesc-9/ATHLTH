import Foundation

/// Lowered-wrist presentation must not ask for an active-workout frame rate.
/// This throttles view-owned TimelineView refreshes only. HealthKit workout
/// collection, alerts and the bright-screen UI continue at normal cadence.
enum ATHLTHAlwaysOnRefreshPolicy {
    static let loweredWristInterval: TimeInterval = 60
}
