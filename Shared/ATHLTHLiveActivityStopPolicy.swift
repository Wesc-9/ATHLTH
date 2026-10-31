import Foundation

/// A Watch workout's HealthKit `.stopped` / `.ended` maps to `.ending`
/// while its result is being persisted. This is terminal for the Live Activity
/// even though the workout result is not yet marked `.completed`.
enum ATHLTHLiveActivityStopPolicy {
    static func shouldDismiss(_ state: WatchWorkoutMirrorState) -> Bool {
        switch state {
        case .ending, .completed, .failed: return true
        case .preparing, .running, .paused: return false
        }
    }

    /// A late update from a stopped session must never recreate its timer.
    /// A different session (new start date) is free to start its own Activity.
    static func mayStart(
        identity: ATHLTHLiveActivitySessionIdentity,
        lastStopped: ATHLTHLiveActivitySessionIdentity?
    ) -> Bool {
        lastStopped?.matches(identity) != true
    }
}
