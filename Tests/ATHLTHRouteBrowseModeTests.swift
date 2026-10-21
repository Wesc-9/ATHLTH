import XCTest
@testable import ATHLTH

final class ATHLTHRouteBrowseModeTests: XCTestCase {
    func testAllThreeRoutePresentationModesPersistByStableID() {
        XCTAssertEqual(
            ATHLTHRouteBrowseMode.allCases,
            [.cards, .list, .map]
        )
        for mode in ATHLTHRouteBrowseMode.allCases {
            XCTAssertEqual(ATHLTHRouteBrowseMode(rawValue: mode.rawValue), mode)
            XCTAssertEqual(mode.id, mode.rawValue)
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.symbol.isEmpty)
        }
    }

    func testUnknownSavedPreferenceFallsBackToCards() {
        let saved = "old_route_view_mode"
        let result = ATHLTHRouteBrowseMode(rawValue: saved) ?? .cards
        XCTAssertEqual(result, .cards)
    }
}
