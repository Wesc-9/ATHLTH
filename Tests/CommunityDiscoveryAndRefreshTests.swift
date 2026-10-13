import XCTest
@testable import ATHLTH

final class CommunityDiscoveryPolicyTests: XCTestCase {
    func testAllCategoryVariantsAndIdentifiersAreStable() {
        XCTAssertEqual(ATHLTHCommunityDiscoveryCategory.allCases.map(\.rawValue), [
            "all", "clubs", "events", "challenges",
        ])
    }

    func testCaseInsensitiveAndNorwegianDiacriticInsensitiveSearch() {
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "trening", in: ["Tréningsklubben", "Tur i fjellet"]
        ))
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "KVELD", in: ["Løping på kvelden"]
        ))
    }

    func testSearchMatchesAllWordsAcrossFields() {
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "Bodø løpetur", in: ["Løpetur", "Bodø sentrum"]
        ))
        XCTAssertFalse(ATHLTHCommunityDiscoveryPolicy.matches(
            "Bodø styrke", in: ["Løpetur", "Bodø sentrum"]
        ))
    }

    func testEmptySearchMatchesPublicRecords() {
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches("   ", in: []))
    }
}

final class CommunityRefreshPolicyTests: XCTestCase {
    func testOnlyFailedAreaAppearsInMessage() {
        let areas = ATHLTHCommunityRefreshPolicy.failedAreas(
            events: false, clubs: true, weekly: false,
            friends: false, messages: false, live: false
        )
        XCTAssertEqual(areas, [.clubs])
        let notice = ATHLTHCommunityRefreshPolicy.notice(for: areas)
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice?.contains(
            ATHLTHCommunityRefreshArea.clubs.localizedTitle
        ) == true)
    }

    func testNoFailureDoesNotShowWarning() {
        let areas = ATHLTHCommunityRefreshPolicy.failedAreas(
            events: false, clubs: false, weekly: false,
            friends: false, messages: false, live: false
        )
        XCTAssertTrue(areas.isEmpty)
        XCTAssertNil(ATHLTHCommunityRefreshPolicy.notice(for: areas))
    }

    func testDuplicatesAreCollapsedInCanonicalOrder() {
        let output = ATHLTHCommunityRefreshPolicy.notice(
            for: [.messages, .events, .messages, .clubs]
        )
        let expected = [
            ATHLTHCommunityRefreshArea.events.localizedTitle,
            ATHLTHCommunityRefreshArea.clubs.localizedTitle,
            ATHLTHCommunityRefreshArea.messages.localizedTitle,
        ]
        XCTAssertNotNil(output)
        for value in expected {
            XCTAssertTrue(output?.contains(value) == true)
        }
    }
}
