import Foundation

/// Carry a cached metric snapshot only when HealthKit has reattached the
/// identical Watch workout. A newly started workout may have the same sport,
/// but must start without the previous one's pulse, distance or calories.
enum ATHLTHWorkoutMirrorContinuity {
    static func mayCarryRecordedMetrics(
        previous: WatchWorkoutLiveSnapshot?,
        newKind: WatchWorkoutKind,
        newStartedAt: Date?
    ) -> Bool {
        guard let previous,
              let previousStart = previous.startedAt,
              let newStartedAt,
              previous.kind == newKind,
              previous.state == .running ||
                  previous.state == .paused ||
                  previous.state == .preparing,
              abs(previousStart.timeIntervalSince(newStartedAt)) < 2
        else { return false }

        return true
    }


    /// WatchConnectivity batches are not guaranteed to be chronological.
    /// Neither a stale active sample nor a result from an earlier workout
    /// may replace the current HealthKit mirror or trigger a second coach cue.
    static func acceptsLiveSnapshot(
        previous: WatchWorkoutLiveSnapshot?,
        incoming: WatchWorkoutLiveSnapshot
    ) -> Bool {
        guard incoming.capturedAt.timeIntervalSince1970.isFinite else {
            return false
        }
        guard let previous else { return true }
        guard previous.kind == incoming.kind else { return false }
        if let originalID = previous.strengthWorkoutID,
           let incomingID = incoming.strengthWorkoutID,
           originalID != incomingID {
            return false
        }
        if let original = previous.startedAt,
           let candidate = incoming.startedAt,
           abs(original.timeIntervalSince(candidate)) >= 2 {
            return false
        }
        if previous.state == .completed || previous.state == .failed {
            return false
        }
        // Stopping HealthKit is irreversible for this session: a queued
        // running/paused update cannot restart its timer while saving.
        if previous.state == .ending &&
            (incoming.state == .running ||
             incoming.state == .paused ||
             incoming.state == .preparing) {
            return false
        }
        // Never rewind even when the new payload is a valid terminal state:
        // an already newer capture must keep ownership of the screen.
        return incoming.capturedAt >= previous.capturedAt
    }

    /// Only a completed Watch-strength mirror for the same ATHLTH session
    /// may finish the iPhone's strength log. Legacy snapshots have no UUID
    /// and must match the actual Watch start closely; a missing start never
    /// grants permission to finish an unrelated recording.
    static func canFinishStrength(
        snapshot: WatchWorkoutLiveSnapshot,
        workoutID: UUID,
        workoutStartedAt: Date
    ) -> Bool {
        guard snapshot.kind == .strength,
              snapshot.state == .completed,
              let startedAt = snapshot.startedAt,
              startedAt.timeIntervalSince1970.isFinite,
              snapshot.capturedAt >= startedAt,
              abs(startedAt.timeIntervalSince(workoutStartedAt)) <= 15
        else { return false }
        if let stableID = snapshot.strengthWorkoutID {
            return stableID == workoutID
        }
        return true
    }

    /// An inactivity response without an explicit workout ID cannot close
    /// a newer Watch mirror snapshot. Watch sends both timestamps in the
    /// same clock domain; a status older than the last accepted snapshot
    /// is stale regardless of which HealthKit workout it describes.
    static func acceptsInactiveWatchActivity(
        snapshot: WatchWorkoutLiveSnapshot,
        activity: WatchWorkoutActivityState
    ) -> Bool {
        guard !activity.isActive,
              snapshot.state != .completed,
              snapshot.state != .failed,
              activity.updatedAt.timeIntervalSince1970.isFinite,
              snapshot.capturedAt.timeIntervalSince1970.isFinite,
              let start = snapshot.startedAt,
              start.timeIntervalSince1970.isFinite else {
            return false
        }
        return activity.updatedAt >= max(start, snapshot.capturedAt)
    }

    /// A late result from another short run must not terminate the new run.
    static func canApplyCompletion(
        snapshot: WatchWorkoutLiveSnapshot,
        kind: WatchWorkoutKind,
        startedAt: Date,
        endedAt: Date,
        strengthWorkoutID: UUID? = nil
    ) -> Bool {
        guard snapshot.kind == kind,
              let currentStart = snapshot.startedAt,
              currentStart.timeIntervalSince1970.isFinite,
              startedAt.timeIntervalSince1970.isFinite,
              endedAt.timeIntervalSince1970.isFinite,
              endedAt >= startedAt,
              abs(currentStart.timeIntervalSince(startedAt)) < 2,
              currentStart <= endedAt else { return false }

        // Multiple same-kind Watch workouts may have started near each
        // other. A captured stable strength ID always outranks timestamps.
        // If a modern mirror has an ID, an unidentifiable late result
        // must not close its HealthKit presentation or Audio Coach lease.
        if kind == .strength, let mirroredID = snapshot.strengthWorkoutID {
            return strengthWorkoutID == mirroredID
        }
        return true
    }

    /// Old HealthKit delegate callbacks can be delivered after a different
    /// session has attached. Never apply them to that newer session.
    static func acceptsDelegateCallback(
        activeSession: ObjectIdentifier?,
        incomingSession: ObjectIdentifier
    ) -> Bool {
        activeSession == incomingSession
    }
}
