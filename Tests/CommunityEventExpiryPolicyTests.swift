import XCTest
@testable import ATHLTH

final class CommunityEventExpiryPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testPlannedEventCancelsAtTwelveHoursNotBefore() {
        XCTAssertFalse(CommunityEventExpiryPolicy.shouldAutoCancel(
            status: "upcoming",
            startsAt: start,
            now: start.addingTimeInterval(12 * 3600 - 1)
        ))
        XCTAssertTrue(CommunityEventExpiryPolicy.shouldAutoCancel(
            status: "upcoming",
            startsAt: start,
            now: start.addingTimeInterval(12 * 3600)
        ))
    }

    func testAlreadyStartedOrCompletedEventIsNeverCancelled() {
        let late = start.addingTimeInterval(48 * 3600)
        for state in ["live", "completed", "cancelled", "draft"] {
            XCTAssertFalse(CommunityEventExpiryPolicy.shouldAutoCancel(
                status: state, startsAt: start, now: late
            ))
        }
        XCTAssertTrue(CommunityEventExpiryPolicy.shouldShowAsUpcoming(
            status: "live", startsAt: start, now: late
        ))
        XCTAssertFalse(CommunityEventExpiryPolicy.shouldShowAsUpcoming(
            status: "upcoming", startsAt: start, now: late
        ))
    }

    func testRecurringClubSeriesIsPreservedUntilRepeatWindowEnds() {
        let now = start.addingTimeInterval(2 * 86400)
        let futureEnd = start.addingTimeInterval(30 * 86400)
        XCTAssertFalse(CommunityEventExpiryPolicy.shouldAutoCancel(
            status: "upcoming", startsAt: start,
            repeatRule: "weekly", repeatUntil: futureEnd, now: now
        ))
        XCTAssertFalse(CommunityEventExpiryPolicy.shouldAutoCancel(
            status: "upcoming", startsAt: start,
            repeatRule: "weekly", repeatUntil: nil, now: now
        ))
        XCTAssertTrue(CommunityEventExpiryPolicy.shouldAutoCancel(
            status: "upcoming", startsAt: start,
            repeatRule: "weekly", repeatUntil: start, now: now
        ))
        XCTAssertTrue(CommunityEventExpiryPolicy.shouldAutoCancel(
            status: "upcoming", startsAt: start, now: now
        ))
    }
}
