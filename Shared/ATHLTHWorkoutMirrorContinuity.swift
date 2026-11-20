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
        // Once Watch has proven its universal ID for this HealthKit
        // recording, late WatchConnectivity packets may not erase or
        // replace that identity, even for non-strength sports.
        if let originalID = previous.universalWorkoutID,
           incoming.universalWorkoutID != originalID {
            return false
        }
        // A snapshot that has already established an exact strength
        // identity may never be updated by an unidentifiable or different
        // strength session. Older Watch versions still work when neither
        // snapshot ever carried a stable strength ID.
        if let originalID = previous.strengthWorkoutID,
           incoming.strengthWorkoutID != originalID {
            return false
        }
        // When an active session established a start timestamp, a later
        // packet with a missing start is not proof of the same recording.
        // Keep the pending/preparing legacy path when no start was known.
        if let original = previous.startedAt {
            guard let candidate = incoming.startedAt,
                  candidate.timeIntervalSince1970.isFinite,
                  abs(original.timeIntervalSince(candidate)) < 2
            else { return false }
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

    /// A watch-inactive state ends the visible timer, but it is NOT proof
    /// that HealthKit has finished saving the workout. Only the correlated
    /// terminal Watch result can move the mirrored session to completed.
    static func stateAfterInactiveWatchActivity(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) -> WatchWorkoutMirrorState {
        snapshot.state == .failed ? .failed : .ending
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
            guard stableID == workoutID else { return false }
        }
        if let universalID = snapshot.universalWorkoutID {
            return universalID == workoutID
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
        strengthWorkoutID: UUID? = nil,
        universalWorkoutID: UUID? = nil
    ) -> Bool {
        guard snapshot.kind == kind,
              let currentStart = snapshot.startedAt,
              currentStart.timeIntervalSince1970.isFinite,
              startedAt.timeIntervalSince1970.isFinite,
              endedAt.timeIntervalSince1970.isFinite,
              endedAt >= startedAt,
              abs(currentStart.timeIntervalSince(startedAt)) < 2,
              currentStart <= endedAt else { return false }

        // A stable original Watch workout ID always outranks timestamps;
        // this also covers repeated same-sport starts and offline result
        // packets from the previous workout.
        if let liveID = snapshot.universalWorkoutID,
           universalWorkoutID != liveID {
            return false
        }
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

 
/// Prepared Today cards have transport identity separate from the original
/// workout. A competing local/remote start must never falsely acknowledge
/// or consume a card simply because Watch happens to be recording.
enum ATHLTHWatchPreparedLaunchConfirmationPolicy {
    static func confirms(
        acknowledgedWorkoutID: UUID?,
        currentWorkoutID: UUID?,
        requestedKind: WatchWorkoutKind,
        activeKind: WatchWorkoutKind,
        isRecording: Bool
    ) -> Bool {
        guard isRecording,
              requestedKind == activeKind,
              let acknowledgedWorkoutID,
              let currentWorkoutID else { return false }
        return acknowledgedWorkoutID == currentWorkoutID
    }
}

 
/// A prepared Watch card is allowed to configure the shared workout manager
/// only when another card is not already awaiting HealthKit/phone permission.
/// This is a transient preflight lock, not a second recording owner.
enum ATHLTHWatchPreparedLaunchReservationPolicy {
    static func mayBegin(pendingID: UUID?) -> Bool {
        pendingID == nil
    }
}
