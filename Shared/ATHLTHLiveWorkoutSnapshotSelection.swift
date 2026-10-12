import Foundation

/// Selects the authoritative live presentation snapshot without starting,
/// stopping, merging or duplicating a HealthKit recording.
enum ATHLTHLiveWorkoutSnapshotSelection {
    static func resolve(
        mirroredWatch: WatchWorkoutLiveSnapshot?,
        phoneWorkout: WatchWorkoutLiveSnapshot?
    ) -> WatchWorkoutLiveSnapshot? {
        // If mirroring has disconnected or ended, a still-active phone
        // workout remains eligible for its own Live Activity and widgets.
        mirroredWatch ?? phoneWorkout
    }
}
