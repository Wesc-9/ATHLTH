import XCTest
@testable import ATHLTH

final class CommunityClubNavigationTests: XCTestCase {
    func testOnlyFourMainClubTabsAreShown() {
        XCTAssertEqual(
            CommunityGroupsTab.visibleTabs,
            [.overview, .activities, .chat, .members]
        )
        XCTAssertFalse(CommunityGroupsTab.visibleTabs.contains(.events))
        XCTAssertFalse(CommunityGroupsTab.visibleTabs.contains(.challenges))
    }

    func testClubActivitiesHaveDistinctSections() {
        XCTAssertEqual(CommunityGroupActivityCategory.allCases, [.events, .challenges])
        XCTAssertNotEqual(
            CommunityGroupActivityCategory.events.localizedTitle,
            CommunityGroupActivityCategory.challenges.localizedTitle
        )
    }

    func testHistoricalEventAndChallengeTabCasesRemainResolvable() {
        XCTAssertTrue(CommunityGroupsTab.allCases.contains(.events))
        XCTAssertTrue(CommunityGroupsTab.allCases.contains(.challenges))
    }
}
