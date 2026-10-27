import XCTest
@testable import ATHLTH

/// Ensures the 2026 Community shell remains exactly three tabs and does not
/// revive the previous fourth-page shortcut menu.
final class ATHLTHCommunityV5NavigationTests: XCTestCase {
    func testCommunityHasExactlyThreeRootDestinations() {
        XCTAssertEqual(ATHLTHCommunityMainTab.allCases,
                       [.overview, .arena, .clubs])
        XCTAssertEqual(
            Set(ATHLTHCommunityMainTab.allCases.map(\.id)).count, 3)
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
