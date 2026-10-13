import XCTest
@testable import ATHLTH

final class ATHLTHGhostFinishPaceCoachTests: XCTestCase {
    func testRequiredPaceForLastHalfKilometre() throws {
        let pace = try XCTUnwrap(
            ATHLTHGhostFinishPaceCoach.requiredSecondsPerKilometre(
                remainingMeters: 500,
                elapsedSeconds: 1_200,
                ghostFinishSeconds: 1_350
            )
        )
        XCTAssertEqual(pace, 300, accuracy: 0.001)
        XCTAssertEqual(ATHLTHGhostFinishPaceCoach.minuteSecondText(pace), "5:00")
    }

    func testNoImpossiblePaceAfterGhostAlreadyFinished() {
        XCTAssertNil(ATHLTHGhostFinishPaceCoach.requiredSecondsPerKilometre(
            remainingMeters: 500,
            elapsedSeconds: 1_400,
            ghostFinishSeconds: 1_350
        ))
    }

    func testUnreliableOrDangerousPaceNotAnnounced() {
        XCTAssertNil(ATHLTHGhostFinishPaceCoach.requiredSecondsPerKilometre(
            remainingMeters: 400,
            elapsedSeconds: 700,
            ghostFinishSeconds: 730
        ))
        XCTAssertNil(ATHLTHGhostFinishPaceCoach.requiredSecondsPerKilometre(
            remainingMeters: .nan,
            elapsedSeconds: 700,
            ghostFinishSeconds: 850
        ))
    }

    func testNoCueForRouteAlreadyComplete() {
        XCTAssertNil(ATHLTHGhostFinishPaceCoach.requiredSecondsPerKilometre(
            remainingMeters: 0,
            elapsedSeconds: 600,
            ghostFinishSeconds: 700
        ))
    }
}
