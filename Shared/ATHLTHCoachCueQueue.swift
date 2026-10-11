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
              cue.event.priority >= .structuredStep,
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
        let chosenIndex = pending.indices.max { left, right in
            if pending[left].event.priority ==
                pending[right].event.priority {
                // Earlier is preferable for the same priority.
                return pending[left].event.createdAt >
                    pending[right].event.createdAt
            }
            return pending[left].event.priority <
                pending[right].event.priority
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
