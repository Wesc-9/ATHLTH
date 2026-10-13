import Foundation
import XCTest
@testable import ATHLTH

final class CommunityDiscoveryAndRefreshPolicyTests: XCTestCase {
    func testDiscoveryMatchesCaseAccentsAndWhitespace() {
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "  lop  TROMS  ",
            in: ["Løpeklubb", "Trøms", "Utholdenhet"]
        ))
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "styrke",
            in: ["STYRKEKLUBBEN"]
        ))
    }

    func testDiscoveryNeedsEverySearchWordButDoesNotNeedOneField() {
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "fjell bodø",
            in: ["Fjelltrening", "Bodø"]
        ))
        XCTAssertFalse(ATHLTHCommunityDiscoveryPolicy.matches(
            "fjell oslo",
            in: ["Fjelltrening", "Bodø"]
        ))
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "",
            in: []
        ))
    }

    func testAllDiscoveryCategoriesHaveDistinctIdentifiersAndTitles() {
        let categories = ATHLTHCommunityDiscoveryCategory.allCases
        XCTAssertEqual(categories.count, 4)
        XCTAssertEqual(Set(categories.map(\.id)).count, categories.count)
        XCTAssertFalse(categories.contains { $0.localizedTitle.isEmpty })
    }

    func testRefreshGroupsProblemsByAffectedArea() {
        let areas = ATHLTHCommunityRefreshPolicy.failedAreas(
            events: false,
            clubs: true,
            weekly: false,
            friends: false,
            messages: true,
            live: false
        )
        XCTAssertEqual(areas, [.clubs, .messages])
        let notice = ATHLTHCommunityRefreshPolicy.notice(for: areas)
        XCTAssertNotNil(notice)
        XCTAssertFalse(notice?.isEmpty ?? true)
    }

    func testSuccessfulRefreshRemovesErrorNotice() {
        let areas = ATHLTHCommunityRefreshPolicy.failedAreas(
            events: false, clubs: false, weekly: false,
            friends: false, messages: false, live: false
        )
        XCTAssertTrue(areas.isEmpty)
        XCTAssertNil(ATHLTHCommunityRefreshPolicy.notice(for: areas))
    }

    func testRefreshNoticeDeduplicatesAreas() {
        let notice = ATHLTHCommunityRefreshPolicy.notice(
            for: [.events, .events, .clubs]
        )
        XCTAssertNotNil(notice)
        XCTAssertEqual(notice?.components(separatedBy: ",").count, 2)
    }
}
