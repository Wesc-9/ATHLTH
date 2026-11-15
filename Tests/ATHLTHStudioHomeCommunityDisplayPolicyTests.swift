import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHStudioHomeCommunityDisplayPolicyTests: XCTestCase {
    func testOnlyPublicClubsNotAlreadyJoinedOrInvitedAppearAsSuggestions() {
        XCTAssertTrue(ATHLTHStudioHomeCommunityDisplayPolicy.isDiscoverable(
            visibility: "public", isMember: false, hasPendingInvitation: false
        ))
        XCTAssertFalse(ATHLTHStudioHomeCommunityDisplayPolicy.isDiscoverable(
            visibility: "private", isMember: false, hasPendingInvitation: false
        ))
        XCTAssertFalse(ATHLTHStudioHomeCommunityDisplayPolicy.isDiscoverable(
            visibility: "public", isMember: true, hasPendingInvitation: false
        ))
        XCTAssertFalse(ATHLTHStudioHomeCommunityDisplayPolicy.isDiscoverable(
            visibility: "public", isMember: false, hasPendingInvitation: true
        ))
    }

    func testCancelledCompletedOrDraftEventsAreNeverPromotedToHome() {
        let now = Date(timeIntervalSince1970: 1_794_744_000)
        let tomorrow = now.addingTimeInterval(86_400)

        for status in ["cancelled", "completed", "draft"] {
            XCTAssertFalse(ATHLTHStudioHomeCommunityDisplayPolicy.isUpcoming(
                status: status, start: tomorrow, now: now
            ))
        }
        XCTAssertTrue(ATHLTHStudioHomeCommunityDisplayPolicy.isUpcoming(
            status: "published", start: tomorrow, now: now
        ))
    }

    func testPastEventsNeverAppearAsFutureEvents() {
        let now = Date(timeIntervalSince1970: 1_794_744_000)
        XCTAssertFalse(ATHLTHStudioHomeCommunityDisplayPolicy.isUpcoming(
            status: "published", start: now.addingTimeInterval(-60), now: now
        ))
    }
}
