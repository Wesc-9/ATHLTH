import XCTest
@testable import ATHLTH

/// Regression coverage for the Community consolidation. Existing events,
/// Club roles and competition records are deliberately left untouched.
final class CommunityConsolidationTests: XCTestCase {
    func testDiscoverySearchHandlesDiacriticsAndCase() {
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "LOPING", in: ["Løping i fjellet", "Bodø"]
        ))
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "bodo", in: ["Turlag i Bodø"]
        ))
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "trening oslo", in: ["Styrketrening", "Oslo sentrum"]
        ))
        XCTAssertFalse(ATHLTHCommunityDiscoveryPolicy.matches(
            "Bergen", in: ["Oslo", "Trening"]
        ))
    }

    func testDiscoveryDoesNotHideContentForEmptySearch() {
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "", in: []
        ))
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "  ", in: ["Any Club"]
        ))
    }

    func testRefreshErrorsAreScopedToAffectedAreas() {
        let failures = ATHLTHCommunityRefreshPolicy.failedAreas(
            events: true,
            clubs: false,
            weekly: false,
            friends: false,
            messages: true,
            live: false
        )
        XCTAssertEqual(failures, [.events, .messages])
        XCTAssertNotNil(ATHLTHCommunityRefreshPolicy.notice(for: failures))
        XCTAssertNil(ATHLTHCommunityRefreshPolicy.notice(for: []))
    }

    func testDiscoveryOffersUniqueDestinationTypes() {
        XCTAssertEqual(
            Set(ATHLTHCommunityDiscoveryCategory.allCases.map(\.id)).count,
            ATHLTHCommunityDiscoveryCategory.allCases.count
        )
    }
}
