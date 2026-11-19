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

    /// A late result from another short run must not terminate the new run.
    static func canApplyCompletion(
        snapshot: WatchWorkoutLiveSnapshot,
        kind: WatchWorkoutKind,
        startedAt: Date,
        endedAt: Date
    ) -> Bool {
        guard snapshot.kind == kind, let currentStart = snapshot.startedAt else { return false }
        return abs(currentStart.timeIntervalSince(startedAt)) < 2 && currentStart <= endedAt
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
