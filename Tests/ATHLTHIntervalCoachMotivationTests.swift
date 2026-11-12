import XCTest
@testable import ATHLTH

final class ATHLTHIntervalCoachMotivationTests: XCTestCase {
    func testHalfwayFollowsEachEffortLength() {
        let settings = ATHLTHIntervalMotivationSettings(halfway: true, finalSeconds: nil)
        for duration in [30.0, 240.0] {
            let midpoint = duration / 2
            XCTAssertNil(ATHLTHIntervalCoachCue.motivation(
                settings, phase: "work", elapsed: midpoint - 1, remaining: midpoint + 1,
                norwegian: true
            ))
            XCTAssertEqual(ATHLTHIntervalCoachCue.motivation(
                settings, phase: "work", elapsed: midpoint, remaining: midpoint,
                norwegian: true
            )?.key, "halfway")
        }
    }

    func testFinalPushAppliesOnlyDuringWorkAndForAValidLeadTime() {
        let settings = ATHLTHIntervalMotivationSettings(halfway: false, finalSeconds: 15)
        XCTAssertEqual(ATHLTHIntervalCoachCue.motivation(
            settings, phase: "work", elapsed: 225, remaining: 15, norwegian: true
        )?.key, "finish")
        XCTAssertNil(ATHLTHIntervalCoachCue.motivation(
            settings, phase: "recovery", elapsed: 225, remaining: 15, norwegian: true
        ))
        XCTAssertNil(ATHLTHIntervalCoachCue.motivation(
            settings, phase: "work", elapsed: 0, remaining: 15, norwegian: true
        ))
    }
}
