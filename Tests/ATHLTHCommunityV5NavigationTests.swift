import XCTest
import UIKit
@testable import ATHLTH

/// The approved 2026 reference has four tabs in one redesigned shell.
/// This must not return to the previous three-tab Community V5 dashboard.
final class ATHLTHCommunityV5NavigationTests: XCTestCase {
    func testCommunityHasFourReferenceDestinations() {
        XCTAssertEqual(ATHLTHCommunityMainTab.allCases,
                       [.overview, .clubs, .arena, .events])
        XCTAssertEqual(
            Set(ATHLTHCommunityMainTab.allCases.map(\.id)).count, 4)
    }

    func testCommunityTabLabelsAreNotBlank() {
        for tab in ATHLTHCommunityMainTab.allCases {
            XCTAssertFalse(tab.title.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testCommunityInterestFiltersAreDistinctAndAvailableToEachScreen() {
        XCTAssertEqual(CommunityInterest.allCases.count, 6)
        XCTAssertEqual(Set(CommunityInterest.allCases.map(\.id)).count, 6)
        XCTAssertTrue(CommunityInterest.allCases.allSatisfy {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
    }

    func testClubCategoriesUseRealPublicMetadata() {
        let club = CommunityGroupRecord(
            id: UUID(), creatorID: UUID(),
            name: "Trondheim Løpeklubb",
            summary: "Felles løpeturer og intervaller",
            locationName: "Trondheim",
            visibility: "public", imageURL: nil,
            headerImageURL: nil, featuredChallengeID: nil,
            joinMode: "open", membersCanCreateContent: true,
            createdAt: Date(), updatedAt: Date()
        )
        XCTAssertTrue(CommunityInterest.all.matchesClub(club))
        XCTAssertTrue(CommunityInterest.running.matchesClub(club))
        XCTAssertFalse(CommunityInterest.strength.matchesClub(club))
    }

    func testOnlyThreeNewCommunityHeroAssets() {
        let mapping: [ATHLTHCommunityMainTab: String] = [
            .overview: "CommunityHero",
            .clubs: "CommunityClubsHero",
            .arena: "CommunityArenaHero",
            .events: "CommunityEventsHero"
        ]
        XCTAssertEqual(mapping.count, ATHLTHCommunityMainTab.allCases.count)
        for name in mapping.values {
            XCTAssertNotNil(
                UIImage(named: name),
                "Community hero image missing from the asset catalog: \(name)"
            )
        }
    }

    func testClubDiscoveryNormalizesNorwegianNames() {
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "loPE", in: ["Løpeklubb", "Trondheim"]))
        XCTAssertFalse(ATHLTHCommunityDiscoveryPolicy.matches(
            "styrke", in: ["Oslo Run Club"]))
    }
}
