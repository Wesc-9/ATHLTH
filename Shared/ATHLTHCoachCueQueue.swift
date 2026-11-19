import Foundation

/// Short-lived, in-memory voice cue. Text never leaves the device and is
/// discarded when a cue expires, a session stops, or the queue is reset.
struct ATHLTHCoachQueuedCue: Hashable {
    let event: ATHLTHCoachEvent
    let text: String
}

/// Priority-aware fallback when a relevant cue cannot interrupt current
/// speech. Critical cues go first, equal priorities are FIFO, stale cues
/// expire and repeated status changes coalesce instead of building a backlog.
/// Routine commentary is never queued.
struct ATHLTHCoachCueQueue {
    static let maximumPending = 6

    private(set) var pending: [ATHLTHCoachQueuedCue] = []

    @discardableResult
    mutating func enqueue(
        _ cue: ATHLTHCoachQueuedCue,
        now: Date = Date()
    ) -> Bool {
        purgeExpired(now: now)
        guard cue.event.isFresh(at: now),
              !cue.text.isEmpty,
              cue.event.priority >= .ghostImportant,
              !pending.contains(where: {
                  $0.event.deliveryID == cue.event.deliveryID
              })
        else {
            return false
        }

        // Only the latest instruction about a changing condition is useful.
        // Distinct structured steps and workout lifecycle cues can coexist.
        if cue.event.kind.coalescesPendingSpeech {
            pending.removeAll {
                $0.event.kind == cue.event.kind
            }
        }

        if pending.count >= Self.maximumPending {
            let lowest = pending.enumerated().min { lhs, rhs in
                if lhs.element.event.priority == rhs.element.event.priority {
                    return lhs.element.event.createdAt <
                        rhs.element.event.createdAt
                }
                return lhs.element.event.priority <
                    rhs.element.event.priority
            }
            guard let lowest,
                  lowest.element.event.priority <=
                    cue.event.priority
            else {
                return false
            }
            pending.remove(at: lowest.offset)
        }

        pending.append(cue)
        return true
    }

    mutating func popNext(
        now: Date = Date()
    ) -> ATHLTHCoachQueuedCue? {
        purgeExpired(now: now)
        guard !pending.isEmpty else {
            return nil
        }
        // Highest priority first. Equal priorities are ordered by
        // timestamp, then original insertion index (stable FIFO even when
        // multiple Watch events carry the exact same timestamp).
        let chosenIndex = pending.indices.min { left, right in
            if pending[left].event.priority != pending[right].event.priority {
                return pending[left].event.priority >
                    pending[right].event.priority
            }
            if pending[left].event.createdAt != pending[right].event.createdAt {
                return pending[left].event.createdAt <
                    pending[right].event.createdAt
            }
            return left < right
        }!
        return pending.remove(at: chosenIndex)
    }

    mutating func purgeExpired(
        now: Date = Date()
    ) {
        pending.removeAll {
            !$0.event.isFresh(at: now)
        }
    }

    mutating func discardObsoleteRunningSteps(currentIndex: Int?) {
        pending.removeAll { cue in
            guard let index = cue.event.runningStepIndex else { return false }
            return index != currentIndex
        }
    }

    /// Pause invalidates movement-dependent voice instructions. Keep only
    /// lifecycle/manual messages; delayed sensor, pace, distance and rest
    /// cues must not be read as if the athlete were still exercising.
    mutating func discardWorkoutMotionCues() {
        pending.removeAll { cue in
            switch cue.event.kind {
            case .runningStep, .routineMilestone, .targetAlert,
                 .routeAlert, .ghostUpdate, .strengthSet, .strengthRest:
                return true
            case .workoutStart, .workoutPause, .workoutResume,
                 .workoutComplete, .manualStatus:
                return false
            }
        }
    }

    /// At finish there is no future interval or set in the same workout.
    /// Never replay a delayed coach cue after the recording has ended.
    mutating func discardForWorkoutCompletion() {
        reset()
    }

    mutating func reset() {
        pending.removeAll(keepingCapacity: true)
    }
}

extension ATHLTHCoachEventKind {
    var coalescesPendingSpeech: Bool {
        switch self {
        case .targetAlert, .routeAlert, .ghostUpdate, .strengthRest,
             .manualStatus:
            return true
        case .workoutStart, .workoutPause, .workoutResume,
             .workoutComplete, .runningStep, .routineMilestone,
             .strengthSet:
            return false
        }
    }
}

/// Shared classification for live cues that do not yet carry an explicit
/// event from their originating engine. No raw metrics or message text are
/// used to identify events.
enum ATHLTHCoachEventFallback {
    static func event(
        for priority: ATHLTHGuidancePriority,
        at now: Date = Date()
    ) -> ATHLTHCoachEvent {
        let kind: ATHLTHCoachEventKind
        switch priority {
        case .routineCoach: kind = .routineMilestone
        case .ghostPeriodic, .ghostImportant: kind = .ghostUpdate
        case .structuredStep: kind = .runningStep
        case .targetCritical: kind = .targetAlert
        case .routeCritical: kind = .routeAlert
        }
        let validity: TimeInterval =
            priority >= .targetCritical ? 6 : 12
        return ATHLTHCoachEvent(
            kind: kind,
            key: UUID().uuidString,
            priority: priority,
            createdAt: now,
            validFor: validity
        )
    }
}
