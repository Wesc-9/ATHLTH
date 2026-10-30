import XCTest
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

    func testClubDiscoveryNormalizesNorwegianNames() {
        XCTAssertTrue(ATHLTHCommunityDiscoveryPolicy.matches(
            "loPE", in: ["Løpeklubb", "Trondheim"]))
        XCTAssertFalse(ATHLTHCommunityDiscoveryPolicy.matches(
            "styrke", in: ["Oslo Run Club"]))
    }
}
