import XCTest
@testable import ATHLTH

final class CommunityDiscoveryPolicyTests: XCTestCase {
    func testDiscoveryMatchesNorwegianAndEnglishWithoutDiacritics() {
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "loping", in: ["Løping", "Styrke"]
        ))
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "fjell bodø", in: ["Fjelløp", "Bodø"]
        ))
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "  ", in: ["Klubb"]
        ))
        XCTAssertFalse(ATHLTHCommunityDiscoveryPolicy.matches(
            "trondheim", in: ["Bodø", "Fjelløp"]
        ))
    }

    func testDiscoverySupportsEachCategory() {
        XCTAssertEqual(ATHLTHCommunityDiscoveryCategory.allCases.count, 4)
        XCTAssertEqual(ATHLTHCommunityDiscoveryCategory.events.symbol, "calendar")
        XCTAssertFalse(ATHLTHCommunityDiscoveryCategory.clubs.localizedTitle.isEmpty)
    }
}

final class CommunityRefreshPolicyTests: XCTestCase {
    func testPartialFailureOnlyHighlightsFailedArea() {
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

    func testSuccessfulRefreshHasNoError() {
        let areas = ATHLTHCommunityRefreshPolicy.failedAreas(
            events: false,
            clubs: false,
            weekly: false,
            friends: false,
            messages: false,
            live: false
        )
        XCTAssertNil(ATHLTHCommunityRefreshPolicy.notice(for: areas))
        XCTAssertNil(ATHLTHCommunityRefreshPolicy.notice(for: []))
    }
}

final class CommunityChallengeEditPolicyTests: XCTestCase {
    func testOnlyNotStartedClubChallengesCanBeEdited() {
        let now = Date()
        let future = now.addingTimeInterval(3600)
        let past = now.addingTimeInterval(-3600)
        let canEdit = ATHLTHCommunityChallengeEditingPolicy.canEdit

        XCTAssertTrue(canEdit(.draft, future, now))
        XCTAssertTrue(canEdit(.upcoming, future, now))
        XCTAssertFalse(canEdit(.upcoming, past, now))
        XCTAssertFalse(canEdit(.live, future, now))
        XCTAssertFalse(canEdit(.completed, future, now))
        XCTAssertFalse(canEdit(.cancelled, future, now))
    }
}
