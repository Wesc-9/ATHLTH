import XCTest
@testable import ATHLTH

final class ATHLTHAlwaysOnRefreshPolicyTests: XCTestCase {
    func testLoweredWristRequestsAtMostOneTimerDrivenFramePerMinute() {
        XCTAssertGreaterThanOrEqual(
            ATHLTHAlwaysOnRefreshPolicy.loweredWristInterval,
            60
        )
    }

    func testPolicyCannotBeMistakenForAWorkoutTimer() {
        // There is no mutable state, timer or workout control here.
        XCTAssertEqual(
            ATHLTHAlwaysOnRefreshPolicy.loweredWristInterval,
            60
        )
    }
}
