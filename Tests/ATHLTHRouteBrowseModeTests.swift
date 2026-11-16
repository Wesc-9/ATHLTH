import XCTest
@testable import ATHLTH

final class ATHLTHRouteBrowseModeTests: XCTestCase {
    func testAllFourRoutePresentationModesPersistByStableID() {
        XCTAssertEqual(
            ATHLTHRouteBrowseMode.allCases,
            [.list, .largeCards, .cards, .map]
        )
        for mode in ATHLTHRouteBrowseMode.allCases {
            XCTAssertEqual(ATHLTHRouteBrowseMode(rawValue: mode.rawValue), mode)
            XCTAssertEqual(mode.id, mode.rawValue)
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.symbol.isEmpty)
        }
    }

    func testLargeCardsAlwaysRequestOneColumn() {
        XCTAssertTrue(ATHLTHRouteBrowseMode.largeCards.forcesSingleColumn)
        for mode in [ATHLTHRouteBrowseMode.list, .cards, .map] {
            XCTAssertFalse(mode.forcesSingleColumn)
        }
        XCTAssertEqual(
            ATHLTHRouteBrowseMode(rawValue: "largeCards"),
            .largeCards
        )
        // Existing saved preferences remain valid after introducing the mode.
        XCTAssertEqual(ATHLTHRouteBrowseMode(rawValue: "cards"), .cards)
        XCTAssertEqual(ATHLTHRouteBrowseMode(rawValue: "list"), .list)
        XCTAssertEqual(ATHLTHRouteBrowseMode(rawValue: "map"), .map)
    }

    func testUnknownSavedPreferenceFallsBackToCards() {
        let saved = "old_route_view_mode"
        let result = ATHLTHRouteBrowseMode(rawValue: saved) ?? .cards
        XCTAssertEqual(result, .cards)
    }
}
