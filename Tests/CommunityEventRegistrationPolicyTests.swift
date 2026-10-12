import XCTest
@testable import ATHLTH

final class CommunityEventRegistrationPolicyTests: XCTestCase {
    func testFuturePlannedEventIsOpenForRSVP() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(
            CommunityEventRegistrationPolicy.canRegister(
                status: "upcoming",
                startsAt: now.addingTimeInterval(60),
                now: now
            )
        )
    }

    func testRSVPClosesExactlyAtStartTimeAndAfter() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for delta in [0.0, -1.0, -20_000.0] {
            XCTAssertFalse(
                CommunityEventRegistrationPolicy.canRegister(
                    status: "upcoming",
                    startsAt: now.addingTimeInterval(delta),
                    now: now
                )
            )
        }
    }

    func testCancelledCompletedAndLiveEventsCannotRegister() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for status in ["live", "cancelled", "completed"] {
            XCTAssertFalse(
                CommunityEventRegistrationPolicy.canRegister(
                    status: status,
                    startsAt: now.addingTimeInterval(3_600),
                    now: now
                ),
                "Unexpected RSVP availability in \(status)"
            )
        }
    }
}
