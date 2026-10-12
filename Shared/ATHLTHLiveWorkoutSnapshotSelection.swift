import Foundation

/// Selects a workout for presentation only. Recording and HealthKit session
/// ownership stay with their individual Watch/iPhone workout engines.
enum ATHLTHLiveWorkoutSnapshotSelection {
    static func resolve(
        mirroredWatch: WatchWorkoutLiveSnapshot?,
        phoneWorkout: WatchWorkoutLiveSnapshot?
    ) -> WatchWorkoutLiveSnapshot? {
        guard let mirroredWatch else { return phoneWorkout }

        // A completed, failed or ending Watch workout may remain cached for
        // results reconciliation while a newly started iPhone workout is
        // active. It cannot replace that new workout's Live Activity.
        if let phoneWorkout,
           [.completed, .failed, .ending].contains(mirroredWatch.state),
           [.preparing, .running, .paused].contains(phoneWorkout.state) {
            return phoneWorkout
        }

        // During an active mirrored workout, Watch is authoritative.
        // Terminal Watch snapshots are retained if no new phone workout is
        // present, so its completed Live Activity can close correctly.
        return mirroredWatch
    }
}
