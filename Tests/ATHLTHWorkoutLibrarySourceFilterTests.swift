import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutLibrarySourceFilterTests: XCTestCase {
    func testFavoritesOnlyExcludesUnstarredWorkoutsFromEverySource() {
        let filter = ATHLTHWorkoutLibrarySourceFilter(
            favoritesOnly: true, mineOnly: false
        )
        // The same rule applies to catalog, scheduled, saved and custom runs.
        XCTAssertFalse(filter.matches(isPersonal: false, isFavorite: false))
        XCTAssertFalse(filter.matches(isPersonal: true, isFavorite: false))
        XCTAssertTrue(filter.matches(isPersonal: false, isFavorite: true))
        XCTAssertTrue(filter.matches(isPersonal: true, isFavorite: true))
    }

    func testMineOnlyIncludesPersonalCopiesButNotCatalogOrScheduledSessions() {
        let filter = ATHLTHWorkoutLibrarySourceFilter(
            favoritesOnly: false, mineOnly: true
        )
        XCTAssertFalse(filter.matches(isPersonal: false, isFavorite: true))
        XCTAssertFalse(filter.matches(isPersonal: false, isFavorite: false))
        XCTAssertTrue(filter.matches(isPersonal: true, isFavorite: false))
    }

    func testMineAndFavoritesUseIntersection() {
        let filter = ATHLTHWorkoutLibrarySourceFilter(
            favoritesOnly: true, mineOnly: true
        )
        XCTAssertTrue(filter.matches(isPersonal: true, isFavorite: true))
        XCTAssertFalse(filter.matches(isPersonal: true, isFavorite: false))
        XCTAssertFalse(filter.matches(isPersonal: false, isFavorite: true))
        XCTAssertFalse(filter.matches(isPersonal: false, isFavorite: false))
    }

    func testNoSourceFilterShowsEverything() {
        let filter = ATHLTHWorkoutLibrarySourceFilter()
        XCTAssertTrue(filter.matches(isPersonal: true, isFavorite: false))
        XCTAssertTrue(filter.matches(isPersonal: false, isFavorite: false))
    }

    func testMineFilterShortCircuitsFavoritesLookupForPublicEntries() {
        let filter = ATHLTHWorkoutLibrarySourceFilter(
            favoritesOnly: true, mineOnly: true
        )
        var performedLookup = false
        func favorite() -> Bool {
            performedLookup = true
            return true
        }
        XCTAssertFalse(filter.matches(isPersonal: false, isFavorite: favorite()))
        XCTAssertFalse(performedLookup)
    }
}
