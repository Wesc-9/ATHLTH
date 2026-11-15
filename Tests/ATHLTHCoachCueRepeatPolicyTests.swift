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
}
