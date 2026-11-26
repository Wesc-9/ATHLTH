import XCTest
import UIKit
@testable import ATHLTH

/// Clubs is a standalone sidebar destination, not a Community tab.
final class ATHLTHCommunityV5NavigationTests: XCTestCase {
    func testCommunityHasThreeDestinationsWithoutClubs() {
        XCTAssertEqual(ATHLTHCommunityMainTab.allCases,
                       [.overview, .arena, .events])
        XCTAssertEqual(
            Set(ATHLTHCommunityMainTab.allCases.map(\.id)).count, 3)
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

    func testOnlyThreeNewCommunityHeroAssets() throws {
        let mapping: [ATHLTHCommunityMainTab: String] = [
            .overview: "CommunityHero",
            .arena: "CommunityArenaHero",
            .events: "CommunityEventsHero"
        ]
        XCTAssertEqual(mapping.count, ATHLTHCommunityMainTab.allCases.count)
        for tab in ATHLTHCommunityMainTab.allCases {
            let name = try XCTUnwrap(mapping[tab])
            XCTAssertEqual(tab.heroAssetName, name)
            XCTAssertNotNil(
                UIImage(named: name),
                "Community hero image missing from the asset catalog: \(name)"
            )
        }
    }

    func testStandaloneClubHubFiltersLocationVisibilityAndMembership() {
        func club(_ name: String, place: String, visibility: String = "public") -> CommunityGroupRecord {
            CommunityGroupRecord(id: UUID(), creatorID: UUID(), name: name,
                summary: "Løping", locationName: place, visibility: visibility,
                imageURL: nil, headerImageURL: nil, featuredChallengeID: nil,
                joinMode: "open", membersCanCreateContent: true,
                createdAt: Date(), updatedAt: Date())
        }
        let local = club("Trondheim Løpeklubb", place: "Trondheim")
        let privateClub = club("Privat", place: "Trondheim", visibility: "private")
        let distant = club("Oslo", place: "Oslo")
        let joined = club("Medlem", place: "Trondheim")
        XCTAssertEqual(ATHLTHClubHubPolicy.discovery(
            [local, privateClub, distant, joined, local], excluded: [joined.id],
            query: "lop", place: "trondheim", interest: .running).map(\.id), [local.id])
    }

    func testClubHubManagementRequiresCurrentAccountsRole() {
        let account = UUID()
        let club = CommunityGroupRecord(id: UUID(), creatorID: UUID(), name: "Club",
            summary: "", locationName: "", visibility: "public", imageURL: nil,
            headerImageURL: nil, featuredChallengeID: nil, joinMode: "open",
            membersCanCreateContent: true, createdAt: Date(), updatedAt: Date())
        let otherAdmin = CommunityGroupMemberRecord(groupID: club.id, userID: UUID(), role: "admin", joinedAt: Date())
        let ownAdmin = CommunityGroupMemberRecord(groupID: club.id, userID: account, role: "admin", joinedAt: Date())
        XCTAssertFalse(ATHLTHClubHubPolicy.manages(club, memberships: [otherAdmin], account: account))
        XCTAssertTrue(ATHLTHClubHubPolicy.manages(club, memberships: [ownAdmin], account: account))
        XCTAssertTrue(ATHLTHClubHubPolicy.manages(club, memberships: [], account: club.creatorID))
    }

    func testClubDiscoveryNormalizesNorwegianNames() {
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "loPE", in: ["Løpeklubb", "Trondheim"]))
        XCTAssertFalse(ATHLTHCommunityDiscoveryPolicy.matches(
            "styrke", in: ["Oslo Run Club"]))
    }
}
