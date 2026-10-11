import XCTest
@testable import ATHLTH

final class AudioCoachReplayMemoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 123_456)

    func testRoutineMessageCanBeReplayedForOnly45Seconds() {
        var memory = ATHLTHCoachReplayMemory()
        memory.remember(
            "One kilometer completed",
            priority: .routineCoach,
            at: now
        )
        XCTAssertEqual(memory.replayableText(at: now), "One kilometer completed")
        XCTAssertNotNil(
            memory.replayableText(at: now.addingTimeInterval(44))
        )
        XCTAssertNil(
            memory.replayableText(at: now.addingTimeInterval(46))
        )
    }

    func testCriticalAndGhostMessagesNeverEnterReplayHistory() {
        var memory = ATHLTHCoachReplayMemory()
        for priority in [
            ATHLTHGuidancePriority.routeCritical,
            .targetCritical, .ghostImportant, .ghostPeriodic
        ] {
            memory.remember(
                "Critical or transient instruction",
                priority: priority,
                at: now
            )
        }
        XCTAssertNil(memory.replayableText(at: now))
    }

    func testCriticalAlertDoesNotReplacePriorRoutineMessage() {
        var memory = ATHLTHCoachReplayMemory()
        memory.remember(
            "Distance 2 kilometers",
            priority: .routineCoach,
            at: now
        )
        memory.remember(
            "Leave the route",
            priority: .routeCritical,
            at: now.addingTimeInterval(1)
        )
        XCTAssertEqual(
            memory.replayableText(at: now.addingTimeInterval(3)),
            "Distance 2 kilometers"
        )
    }

    func testStructuredAndManualStatusAreEligible() {
        var memory = ATHLTHCoachReplayMemory()
        memory.remember(
            "Next interval",
            priority: .structuredStep,
            at: now
        )
        XCTAssertEqual(memory.replayableText(at: now), "Next interval")
    }

    func testOlderAndFutureMessagesCannotBeReplayed() {
        var memory = ATHLTHCoachReplayMemory()
        memory.remember("Distance 1 kilometer", priority: .routineCoach, at: now)
        XCTAssertNil(
            memory.replayableText(at: now.addingTimeInterval(-10))
        )
        XCTAssertNil(
            memory.replayableText(at: now.addingTimeInterval(50))
        )
    }

    func testNewWorkoutResetClearsTextAndDate() {
        var memory = ATHLTHCoachReplayMemory()
        memory.remember("Workout started", priority: .structuredStep, at: now)
        memory.reset()
        XCTAssertNil(memory.text)
        XCTAssertNil(memory.spokenAt)
        XCTAssertNil(memory.replayableText(at: now))
    }

    func testBlankTextDoesNotEraseLastMessage() {
        var memory = ATHLTHCoachReplayMemory()
        memory.remember("Time 10 minutes", priority: .routineCoach, at: now)
        memory.remember(
            "   ",
            priority: .routineCoach,
            at: now.addingTimeInterval(1)
        )
        XCTAssertEqual(memory.replayableText(at: now), "Time 10 minutes")
    }
}
