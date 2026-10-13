import XCTest
@testable import ATHLTH

final class CommunityAgendaPolicyTests: XCTestCase {
    func testClubEventRequiresParticipationOrOwnership() {
        let user = UUID()
        let other = UUID()
        let future = Date().addingTimeInterval(3600)
        let now = Date()
        let check = ATHLTHCommunityAgendaPolicy.includesClubEvent

        XCTAssertFalse(check(future, "scheduled", other, user, nil, now))
        XCTAssertTrue(check(future, "scheduled", user, user, nil, now))
        XCTAssertTrue(check(future, "scheduled", other, user, "going", now))
        XCTAssertTrue(check(future, "scheduled", other, user, "maybe", now))
        XCTAssertTrue(check(future, "scheduled", other, user, "waitlist", now))
        XCTAssertFalse(check(future, "scheduled", other, user, "declined", now))
    }

    func testCancelledDraftCompletedAndPastClubEventsAreExcluded() {
        let user = UUID()
        let future = Date().addingTimeInterval(3600)
        let past = Date().addingTimeInterval(-3600)
        let now = Date()
        let check = ATHLTHCommunityAgendaPolicy.includesClubEvent

        for status in ["cancelled", "draft", "completed"] {
            XCTAssertFalse(check(future, status, user, user, "going", now))
        }
        XCTAssertFalse(check(past, "scheduled", user, user, "going", now))
    }
}
