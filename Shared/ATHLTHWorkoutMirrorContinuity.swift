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

    /// Old HealthKit delegate callbacks can be delivered after a different
    /// session has attached. Never apply them to that newer session.
    static func acceptsDelegateCallback(
        activeSession: ObjectIdentifier?,
        incomingSession: ObjectIdentifier
    ) -> Bool {
        activeSession == incomingSession
    }
}
