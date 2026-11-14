import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHLibraryPaginationTests: XCTestCase {
    func testAllLibrariesOfferSameThreeScopes() {
        XCTAssertEqual(
            ATHLTHUnifiedLibraryScope.allCases,
            [.athlth, .mine, .favorites]
        )
        XCTAssertEqual(ATHLTHUnifiedLibraryScope.athlth.title,
                       ATHLTHLocalization.choose(
                        english: "Public", norwegian: "Offentlig"
                       ))
        XCTAssertEqual(ATHLTHUnifiedLibraryScope.mine.rawValue, "mine")
        XCTAssertEqual(ATHLTHUnifiedLibraryScope.favorites.rawValue, "favorites")
    }

    func testFirstPageNeverIncludesMoreThan50Cards() {
        let entries = Array(0..<204)
        let initial = ATHLTHLibraryPagination.visible(
            entries, limit: ATHLTHLibraryPagination.pageSize
        )
        XCTAssertEqual(initial.count, 50)
        XCTAssertEqual(initial.first, 0)
        XCTAssertEqual(initial.last, 49)
        XCTAssertEqual(ATHLTHLibraryPagination.visible([Int](), limit: 50).count, 0)
        XCTAssertEqual(ATHLTHLibraryPagination.visible(entries, limit: 0).count, 0)
    }

    func testLoadMoreAddsOnlyAnother50() {
        let entries = Array(0..<143)
        XCTAssertEqual(ATHLTHLibraryPagination.visible(entries, limit: 50).count, 50)
        XCTAssertEqual(ATHLTHLibraryPagination.visible(entries, limit: 100).count, 100)
        XCTAssertEqual(ATHLTHLibraryPagination.visible(entries, limit: 150).count, 143)
    }

    func testFilteringBeforePagingStillFindsLateMatches() {
        let records = (0..<201).map { "Route-\($0)" }
        let selected = records.filter { $0.localizedStandardContains("Route-200") }
        XCTAssertEqual(ATHLTHLibraryPagination.visible(selected, limit: 50), ["Route-200"])
        XCTAssertTrue(ATHLTHLibraryPagination.visible(records, limit: 50).count == 50)
    }

    func testCombinedWorkoutAndPlanGroupsShareOneVisibleBudget() {
        let firstGroup = Array(0..<33)
        let secondGroup = Array(100..<153)
        let firstShown = ATHLTHLibraryPagination.visible(firstGroup, limit: 50)
        let secondShown = ATHLTHLibraryPagination.visible(
            secondGroup, limit: max(0, 50 - firstShown.count)
        )
        XCTAssertEqual(firstShown.count + secondShown.count, 50)
        XCTAssertEqual(secondShown.last, 116)
    }
}
