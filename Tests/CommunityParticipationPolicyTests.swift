import XCTest
@testable import ATHLTH

final class CommunityParticipationPolicyTests: XCTestCase {
    func testPublicAndClubEventsUseIdenticalParticipationStates() {
        XCTAssertEqual(ATHLTHCommunityRSVPDecision.going.rawValue, "going")
        XCTAssertEqual(ATHLTHCommunityRSVPDecision.maybe.rawValue, "maybe")
        XCTAssertEqual(ATHLTHCommunityRSVPDecision.notGoing.rawValue, "not_going")
        XCTAssertEqual(Set(ATHLTHCommunityRSVPDecision.allCases.map(\.id)).count, 3)
        XCTAssertTrue(ATHLTHCommunityRSVPDecision.allCases.allSatisfy {
            !$0.localizedTitle.isEmpty && !$0.symbol.isEmpty
        })
    }

    func testWaitlistedParticipationIsDisplayedAsGoingNotDeclined() {
        XCTAssertEqual(
            ATHLTHCommunityRSVPDecision.resolvedStatus("waitlist"),
            .going
        )
        XCTAssertEqual(
            ATHLTHCommunityRSVPDecision.resolvedStatus("not_going"),
            .notGoing
        )
    }

    func testUnselectedAndUnknownRSVPsStayUnselected() {
        XCTAssertNil(ATHLTHCommunityRSVPDecision.resolvedStatus(nil))
        XCTAssertNil(ATHLTHCommunityRSVPDecision.resolvedStatus("unknown"))
    }
}
