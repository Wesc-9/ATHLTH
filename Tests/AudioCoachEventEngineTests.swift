import XCTest
@testable import ATHLTH

final class AudioCoachEventEngineTests: XCTestCase {
    private let started = Date(timeIntervalSince1970: 10_000)

    private func event(
        _ kind: ATHLTHCoachEventKind = .routineMilestone,
        key: String = "distance-1000",
        priority: ATHLTHGuidancePriority = .routineCoach,
        validFor: TimeInterval = 10
    ) -> ATHLTHCoachEvent {
        ATHLTHCoachEvent(
            kind: kind,
            key: key,
            priority: priority,
            createdAt: started,
            validFor: validFor
        )
    }

    func testDeliversOnceForSameMilestoneKey() {
        var ledger = ATHLTHCoachEventLedger()
        let milestone = event()
        XCTAssertTrue(ledger.canDeliver(milestone, now: started))
        ledger.didDeliver(milestone, now: started)
        XCTAssertFalse(ledger.canDeliver(milestone, now: started))
        XCTAssertFalse(
            ledger.canDeliver(
                event(key: "distance-1000"),
                now: started.addingTimeInterval(1)
            )
        )
        XCTAssertTrue(
            ledger.canDeliver(
                event(key: "distance-2000"),
                now: started.addingTimeInterval(1)
            )
        )
    }

    func testEventKindIsPartOfIdentity() {
        var ledger = ATHLTHCoachEventLedger()
        ledger.didDeliver(event(.runningStep, key: "2"), now: started)
        XCTAssertTrue(
            ledger.canDeliver(
                event(.strengthSet, key: "2"),
                now: started
            )
        )
    }

    func testExpiredOrFutureEventCannotPlay() {
        let milestone = event(validFor: 5)
        let ledger = ATHLTHCoachEventLedger()
        XCTAssertTrue(ledger.canDeliver(milestone, now: started))
        XCTAssertFalse(
            ledger.canDeliver(
                milestone,
                now: started.addingTimeInterval(6)
            )
        )
        XCTAssertFalse(
            ledger.canDeliver(
                milestone,
                now: started.addingTimeInterval(-3)
            )
        )
    }

    func testInvalidKeyOrNegativeLifetimeIsRejected() {
        let ledger = ATHLTHCoachEventLedger()
        XCTAssertFalse(ledger.canDeliver(
            event(key: ""),
            now: started
        ))
        XCTAssertFalse(ledger.canDeliver(
            event(validFor: -10),
            now: started.addingTimeInterval(1)
        ))
    }

    func testARejectedEventDoesNotMarkDelivery() {
        var ledger = ATHLTHCoachEventLedger()
        let later = event(key: "runnable")
        // The priority gate may drop a routine cue while critical speech
        // is playing; only a successful delivery records this event.
        XCTAssertTrue(ledger.canDeliver(later, now: started))
        XCTAssertTrue(
            ledger.canDeliver(
                later,
                now: started.addingTimeInterval(1)
            )
        )
        ledger.didDeliver(later, now: started.addingTimeInterval(1))
        XCTAssertFalse(
            ledger.canDeliver(
                later,
                now: started.addingTimeInterval(2)
            )
        )
    }

    func testLedgerCanResetForNextWorkout() {
        var ledger = ATHLTHCoachEventLedger()
        let start = event(.workoutStart, key: "ready")
        ledger.didDeliver(start, now: started)
        XCTAssertFalse(ledger.canDeliver(start, now: started))
        ledger.reset()
        XCTAssertTrue(ledger.canDeliver(start, now: started))
    }

    func testLedgerDoesNotGrowUnbounded() {
        var ledger = ATHLTHCoachEventLedger()
        for index in 0..<(ATHLTHCoachEventLedger.maxEntries + 15) {
            ledger.didDeliver(
                event(key: "milestone-\(index)"),
                now: started
            )
        }
        XCTAssertEqual(
            ledger.deliveredIDs.count,
            ATHLTHCoachEventLedger.maxEntries
        )
        XCTAssertTrue(
            ledger.canDeliver(
                event(key: "milestone-0"),
                now: started
            )
        )
        XCTAssertFalse(
            ledger.canDeliver(
                event(key: "milestone-\(ATHLTHCoachEventLedger.maxEntries + 14)"),
                now: started
            )
        )
    }

    func testTypesRepresentDifferentWorkoutCues() {
        let kinds: [ATHLTHCoachEventKind] = [
            .workoutStart, .workoutPause, .workoutResume,
            .workoutComplete, .runningStep, .routineMilestone,
            .targetAlert, .routeAlert, .ghostUpdate, .strengthSet,
            .strengthRest, .manualStatus
        ]
        XCTAssertEqual(Set(kinds).count, 12)
    }
}
