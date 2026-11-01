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

    func testApprovedCommunityReferenceArtworkIsBundled() {
        for name in [
            "CommunityClubsFeatured",
            "CommunityClubsRecommendedHike",
            "CommunityClubsRecommendedCity",
            "CommunityArenaFeatured",
            "CommunityEventsFeatured",
            "CommunityEventsRunning",
            "CommunityEventsYoga",
            "CommunityEventsStrength"
        ] {
            XCTAssertNotNil(
                UIImage(named: name),
                "Missing photo asset from approved Community reference: \(name)"
            )
        }
    }

    func testCommunityEventFallbackArtworkMatchesActivity() {
        XCTAssertEqual(
            ATHLTHCommunityReferenceArtwork.eventFallback(activity: "running"),
            "CommunityEventsRunning"
        )
        XCTAssertEqual(
            ATHLTHCommunityReferenceArtwork.eventFallback(activity: "strength"),
            "CommunityEventsStrength"
        )
        XCTAssertEqual(
            ATHLTHCommunityReferenceArtwork.eventFallback(activity: "yoga"),
            "CommunityEventsYoga"
        )
        XCTAssertEqual(
            ATHLTHCommunityReferenceArtwork.eventFallback(
                activity: "hiking", featured: true
            ),
            "CommunityEventsFeatured"
        )
    }

    func testClubDiscoveryNormalizesNorwegianNames() {
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "loPE", in: ["Løpeklubb", "Trondheim"]))
        XCTAssertFalse(ATHLTHCommunityDiscoveryPolicy.matches(
            "styrke", in: ["Oslo Run Club"]))
    }
}
