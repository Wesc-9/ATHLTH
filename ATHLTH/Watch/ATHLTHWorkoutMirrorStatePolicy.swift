import HealthKit

/// HealthKit session shutdown is not equivalent to a persisted workout.
/// Only the actual Watch workout result may transition a mirrored workout
/// to .completed; keep the mirror alive until that result is acknowledged.
enum ATHLTHWorkoutMirrorStatePolicy {
    static func state(for sessionState: HKWorkoutSessionState) -> WatchWorkoutMirrorState {
        switch sessionState {
        case .running: return .running
        case .paused: return .paused
        case .ended, .stopped: return .ending
        case .prepared, .notStarted: return .preparing
        @unknown default: return .preparing
        }
    }
}
