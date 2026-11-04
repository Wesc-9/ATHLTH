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
    /// The Watch owns heart rate and recording, while the iPhone strength
    /// session owns its current exercise, selected set and rest transition.
    /// Only merge matching recordings: an older cached workout must never
    /// replace the name or set progress of the current session.
    static func enrichStrength(
        _ mirrored: WatchWorkoutLiveSnapshot?,
        local: WatchStrengthSessionSnapshot?,
        localStartedAt: Date?,
        displayName: String?
    ) -> WatchWorkoutLiveSnapshot? {
        guard var mirrored,
              mirrored.kind == .strength,
              [.preparing, .running, .paused].contains(mirrored.state),
              let local,
              let localStartedAt,
              let mirroredStartedAt = mirrored.startedAt,
              abs(localStartedAt.timeIntervalSince(mirroredStartedAt)) <= 180,
              local.setCount > 0 else {
            return mirrored
        }

        mirrored.strengthExerciseName = displayName ?? local.exerciseName
        mirrored.strengthSetCount = local.setCount
        mirrored.strengthSetIndex = min(max(local.setIndex + 1, 1), local.setCount)
        mirrored.strengthReps =
            local.targetKindRaw == "reps" ? local.draftReps : nil
        mirrored.strengthWeightKilograms =
            local.loadKindRaw == "weightKilograms" ? local.draftWeightKilograms : nil
        mirrored.strengthRestEndsAt = local.isResting ? local.restEndsAt : nil
        mirrored.strengthTimedSetTargetSeconds =
            local.targetKindRaw == "time" ? local.draftDurationSeconds : nil
        mirrored.strengthTimedSetSecondsAtSnapshot =
            local.targetKindRaw == "time"
                ? local.timedSetCountdown?.remaining(at: Date()) : nil
        mirrored.strengthTimedSetResumedAt =
            local.targetKindRaw == "time"
                ? local.timedSetCountdown?.resumedAt : nil

        if local.currentExerciseComplete && local.hasNextExercise {
            mirrored.strengthNextExerciseName =
                local.exerciseQueue?
                    .first(where: {
                        $0.index > local.exerciseIndex && $0.isCompleted != true
                    })?.name
                ?? local.exerciseQueue?
                    .first(where: {
                        $0.index < local.exerciseIndex && $0.isCompleted != true
                    })?.name
        } else {
            mirrored.strengthNextExerciseName = nil
        }
        mirrored.capturedAt = max(mirrored.capturedAt, local.updatedAt)
        return mirrored
    }

}
