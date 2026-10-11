import XCTest
@testable import ATHLTH

final class AudioCoachCueQueueTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 10_000)

    private func cue(
        _ kind: ATHLTHCoachEventKind,
        key: String,
        priority: ATHLTHGuidancePriority,
        offset: TimeInterval = 0,
        validFor: TimeInterval = 15
    ) -> ATHLTHCoachQueuedCue {
        let event = ATHLTHCoachEvent(
            kind: kind,
            key: key,
            priority: priority,
            createdAt: origin.addingTimeInterval(offset),
            validFor: validFor
        )
        return ATHLTHCoachQueuedCue(
            event: event,
            text: "A safe test phrase"
        )
    }

    func testRoutineUpdatesAreNeverQueued() {
        var queue = ATHLTHCoachCueQueue()
        XCTAssertFalse(queue.enqueue(
            cue(.routineMilestone, key: "1km", priority: .routineCoach),
            now: origin
        ))
        XCTAssertNil(queue.popNext(now: origin))
    }

    func testCriticalAlertsLeadStructuredInstructions() {
        var queue = ATHLTHCoachCueQueue()
        XCTAssertTrue(queue.enqueue(
            cue(.runningStep, key: "interval3", priority: .structuredStep),
            now: origin
        ))
        XCTAssertTrue(queue.enqueue(
            cue(.targetAlert, key: "pulseHigh", priority: .targetCritical, offset: 1),
            now: origin.addingTimeInterval(1)
        ))
        XCTAssertTrue(queue.enqueue(
            cue(.routeAlert, key: "offCourse", priority: .routeCritical, offset: 2),
            now: origin.addingTimeInterval(2)
        ))

        XCTAssertEqual(queue.popNext(now: origin.addingTimeInterval(3))?.event.kind, .routeAlert)
        XCTAssertEqual(queue.popNext(now: origin.addingTimeInterval(3))?.event.kind, .targetAlert)
        XCTAssertEqual(queue.popNext(now: origin.addingTimeInterval(3))?.event.kind, .runningStep)
    }

    func testImportantGhostUpdateIsQueuedButPeriodicGhostIsNot() {
        var queue = ATHLTHCoachCueQueue()
        XCTAssertFalse(queue.enqueue(
            cue(.ghostUpdate, key: "periodic", priority: .ghostPeriodic),
            now: origin
        ))
        XCTAssertTrue(queue.enqueue(
            cue(.ghostUpdate, key: "leadChange", priority: .ghostImportant),
            now: origin
        ))
        XCTAssertEqual(
            queue.popNext(now: origin)?.event.key,
            "leadChange"
        )
    }

    func testSamePriorityUsesOldestCueFirst() {
        var queue = ATHLTHCoachCueQueue()
        XCTAssertTrue(queue.enqueue(
            cue(.runningStep, key: "first", priority: .structuredStep),
            now: origin
        ))
        XCTAssertTrue(queue.enqueue(
            cue(.runningStep, key: "second", priority: .structuredStep, offset: 1),
            now: origin.addingTimeInterval(1)
        ))
        XCTAssertEqual(queue.popNext(now: origin.addingTimeInterval(2))?.event.key, "first")
        XCTAssertEqual(queue.popNext(now: origin.addingTimeInterval(2))?.event.key, "second")
    }

    func testCoalescesOlderTargetAlertsAndKeepsOtherKinds() {
        var queue = ATHLTHCoachCueQueue()
        XCTAssertTrue(queue.enqueue(
            cue(.targetAlert, key: "low", priority: .targetCritical),
            now: origin
        ))
        XCTAssertTrue(queue.enqueue(
            cue(.runningStep, key: "next", priority: .structuredStep),
            now: origin
        ))
        XCTAssertTrue(queue.enqueue(
            cue(.targetAlert, key: "high", priority: .targetCritical, offset: 1),
            now: origin.addingTimeInterval(1)
        ))
        XCTAssertEqual(queue.pending.count, 2)
        XCTAssertEqual(queue.popNext(now: origin.addingTimeInterval(2))?.event.key, "high")
        XCTAssertEqual(queue.popNext(now: origin.addingTimeInterval(2))?.event.key, "next")
    }

    func testRejectsDuplicateKeysAndExpiredAlerts() {
        var queue = ATHLTHCoachCueQueue()
        let event = cue(.runningStep, key: "three", priority: .structuredStep)
        XCTAssertTrue(queue.enqueue(event, now: origin))
        XCTAssertFalse(queue.enqueue(event, now: origin.addingTimeInterval(1)))
        XCTAssertFalse(queue.enqueue(
            cue(.targetAlert, key: "old", priority: .targetCritical, validFor: 2),
            now: origin.addingTimeInterval(5)
        ))
        XCTAssertNil(queue.popNext(now: origin.addingTimeInterval(20)))
    }

    func testQueueBoundAndLowerPriorityCannotReplaceCritical() {
        var queue = ATHLTHCoachCueQueue()
        for idx in 0..<ATHLTHCoachCueQueue.maximumPending {
            XCTAssertTrue(queue.enqueue(
                cue(.runningStep, key: "stage-\(idx)", priority: .structuredStep),
                now: origin
            ))
        }
        XCTAssertFalse(queue.enqueue(
            cue(.runningStep, key: "stage-overflow", priority: .routineCoach),
            now: origin
        ))
        XCTAssertEqual(queue.pending.count, ATHLTHCoachCueQueue.maximumPending)

        XCTAssertTrue(queue.enqueue(
            cue(.routeAlert, key: "urgent", priority: .routeCritical),
            now: origin
        ))
        XCTAssertEqual(queue.pending.count, ATHLTHCoachCueQueue.maximumPending)
        XCTAssertEqual(queue.popNext(now: origin)?.event.key, "urgent")
    }

    func testResetDiscardsQueuedSpokenText() {
        var queue = ATHLTHCoachCueQueue()
        XCTAssertTrue(queue.enqueue(
            cue(.runningStep, key: "stage", priority: .structuredStep),
            now: origin
        ))
        queue.reset()
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertNil(queue.popNext(now: origin))
    }

    func testFallbackTypeDoesNotContainRawMessageData() {
        XCTAssertEqual(
            ATHLTHCoachEventFallback.event(
                for: .routeCritical,
                at: origin
            ).kind,
            .routeAlert
        )
        XCTAssertEqual(
            ATHLTHCoachEventFallback.event(
                for: .targetCritical,
                at: origin
            ).priority,
            .targetCritical
        )
    }
}
