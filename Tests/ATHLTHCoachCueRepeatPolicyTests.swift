import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCoachCueRepeatPolicyTests: XCTestCase {
    func testSameCueFromTwoSourcesIsOnlyAcceptedOnce() {
        var policy = ATHLTHCoachCueRepeatPolicy()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(policy.shouldAccept("Distanse 1 kilometer.", at: now))
        XCTAssertFalse(policy.shouldAccept("distanse 1 kilometer",
            at: now.addingTimeInterval(1)))
        XCTAssertTrue(policy.shouldAccept("Distanse 1 kilometer",
            at: now.addingTimeInterval(13)))
    }

    func testDifferentCoachInstructionsAreNotSuppressed() {
        var policy = ATHLTHCoachCueRepeatPolicy()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(policy.shouldAccept("Neste intervall om ti sekunder.", at: now))
        XCTAssertTrue(policy.shouldAccept("Pulssone 4", at: now))
    }

    func testCombinedRoutineMetricsAreNotRepeated() {
        XCTAssertEqual(
            ATHLTHCoachCueRepeatPolicy.uniqueSentences([
                "Distanse 1 kilometer",
                "distanse 1 kilometer.",
                "Puls 140"
            ]),
            ["Distanse 1 kilometer", "Puls 140"]
        )
    }
    func testRequestDoesNotConsumeRepeatWindowBeforePlayback() {
        var policy = ATHLTHCoachCueRepeatPolicy()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(policy.canAccept("Kilometer en.", at: now))
        XCTAssertTrue(policy.canAccept("KILOMETER EN", at: now.addingTimeInterval(1)))
        // Only a confirmed Azure/AVSpeech start should consume the window.
        policy.didSpeak("Kilometer en.", at: now.addingTimeInterval(2))
        XCTAssertFalse(policy.canAccept("kilometer en", at: now.addingTimeInterval(3)))
        XCTAssertTrue(policy.canAccept("Kilometer en", at: now.addingTimeInterval(15)))
        policy.reset()
        XCTAssertTrue(policy.canAccept("Kilometer en", at: now.addingTimeInterval(3)))
    }


}
