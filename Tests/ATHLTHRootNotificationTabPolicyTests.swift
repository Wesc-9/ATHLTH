import XCTest
@testable import ATHLTH

final class ATHLTHRootNotificationTabPolicyTests: XCTestCase {
    func testCommunityEventsOpenCommunityTab() {
        for kind in [
            "new_message", "FRIEND_ACCEPTED", "challenge_invite",
            "workout_reaction", "event_reminder"
        ] {
            XCTAssertEqual(ATHLTHRootNotificationTabPolicy.destinationTab(for: kind), 4)
        }
    }

    func testUnknownButPresentNotificationDefaultsToHome() {
        XCTAssertEqual(
            ATHLTHRootNotificationTabPolicy.destinationTab(for: "billing_update"), 0
        )
    }

    func testMissingOrWhitespaceKindDoesNotHijackCurrentTab() {
        XCTAssertNil(ATHLTHRootNotificationTabPolicy.destinationTab(for: nil))
        XCTAssertNil(ATHLTHRootNotificationTabPolicy.destinationTab(for: ""))
        XCTAssertNil(ATHLTHRootNotificationTabPolicy.destinationTab(for: "  "))
    }
}
