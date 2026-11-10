import XCTest
@testable import ATHLTH

final class ATHLTHiPadLibraryNavigationTests: XCTestCase {
    @MainActor
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

    @MainActor
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

    @MainActor
    func testLibraryPageOrderStartsWithUnifiedHub() {
        XCTAssertEqual(ATHLTHStudioLibraryPage.allCases.first, .overview)
        XCTAssertTrue(ATHLTHStudioLibraryPage.allCases.contains(.exercises))
        XCTAssertTrue(ATHLTHStudioLibraryPage.allCases.contains(.routes))
        XCTAssertTrue(ATHLTHStudioLibraryPage.allCases.contains(.workouts))
        XCTAssertTrue(ATHLTHStudioLibraryPage.allCases.contains(.trainingPlans))
    }
    @MainActor
    func testGhostAndProfileHaveDedicatedStudioDestinationPages() {
        let ghost = ATHLTHiPadSidebarPageView(
            destination: .ghostRace, onBack: {}
        )
        let profile = ATHLTHiPadSidebarPageView(
            destination: .profile, onBack: {}
        )
        let arena = ATHLTHiPadSidebarPageView(
            destination: .arena, onBack: {}
        )
        XCTAssertEqual(ghost.title, "Ghost Race")
        XCTAssertEqual(arena.title, "Arena")
        XCTAssertFalse(profile.title.isEmpty)
        XCTAssertNotEqual(profile.title, ghost.title)
    }

}
