import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHiPadLibraryNavigationTests: XCTestCase {
    func testEachSidebarCollectionMapsToItsCanonicalFullSizeLibrary() {
        XCTAssertEqual(
            ATHLTHPersonalLibrarySection.exercises.studioLibraryPage,
            .exercises
        )
        XCTAssertEqual(
            ATHLTHPersonalLibrarySection.workouts.studioLibraryPage,
            .workouts
        )
        XCTAssertEqual(
            ATHLTHPersonalLibrarySection.trainingPlans.studioLibraryPage,
            .trainingPlans
        )
        XCTAssertEqual(
            ATHLTHPersonalLibrarySection.routes.studioLibraryPage,
            .routes
        )
    }

    func testLibraryPagesAreDistinctAndAccessibleFromStudio() {
        XCTAssertEqual(ATHLTHStudioLibraryPage.allCases.count, 5)
        XCTAssertEqual(
            Set(ATHLTHStudioLibraryPage.allCases.map(\.id)).count,
            5
        )
        for page in ATHLTHStudioLibraryPage.allCases {
            XCTAssertFalse(page.title.isEmpty)
            XCTAssertFalse(page.symbol.isEmpty)
            XCTAssertFalse(page.detail.isEmpty)
        }
    }

    func testLibraryPageOrderStartsWithUnifiedHub() {
        XCTAssertEqual(ATHLTHStudioLibraryPage.allCases.first, .overview)
        XCTAssertTrue(ATHLTHStudioLibraryPage.allCases.contains(.exercises))
        XCTAssertTrue(ATHLTHStudioLibraryPage.allCases.contains(.routes))
        XCTAssertTrue(ATHLTHStudioLibraryPage.allCases.contains(.workouts))
        XCTAssertTrue(ATHLTHStudioLibraryPage.allCases.contains(.trainingPlans))
    }
}
