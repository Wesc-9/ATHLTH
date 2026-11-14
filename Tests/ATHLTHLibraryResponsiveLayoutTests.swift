import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHLibraryResponsiveLayoutTests: XCTestCase {
    func testPhoneKeepsItsCompactGridAndSingleListColumn() {
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.columns(
                mode: .grid, width: 390, reservedHorizontalSpace: 50
            ).count, 3
        )
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.columns(
                mode: .list, width: 390, reservedHorizontalSpace: 36
            ).count, 1
        )
        XCTAssertEqual(ATHLTHLibraryResponsiveLayout.hubColumns(for: 390).count, 2)
    }

    func testUserCanChooseTwoOrThreePhoneColumns() {
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.columns(
                mode: .grid, width: 390,
                reservedHorizontalSpace: 50,
                preferredColumns: 2
            ).count, 2
        )
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.columns(
                mode: .grid, width: 390,
                reservedHorizontalSpace: 50,
                preferredColumns: 3
            ).count, 3
        )
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.columns(
                mode: .list, width: 390,
                reservedHorizontalSpace: 50,
                preferredColumns: 3
            ).count, 1
        )
    }

    func testIPadCanFitFiveButNeverForcesFiveInNarrowWindows() {
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.columns(
                mode: .grid, width: 1400,
                reservedHorizontalSpace: 50,
                preferredColumns: 5
            ).count, 5
        )
        XCTAssertLessThanOrEqual(
            ATHLTHLibraryResponsiveLayout.columns(
                mode: .grid, width: 440,
                reservedHorizontalSpace: 50,
                preferredColumns: 5
            ).count, 3
        )
    }

    func testIPadPortraitUsesAvailableWidth() {
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.columns(
                mode: .list, width: 1024, reservedHorizontalSpace: 36
            ).count, 2
        )
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.columns(
                mode: .grid, width: 1024, reservedHorizontalSpace: 50
            ).count, 4
        )
        XCTAssertEqual(ATHLTHLibraryResponsiveLayout.hubColumns(for: 1024).count, 3)
    }

    func testIPadLandscapeCanShowFiveCardsOrTwoReadableRows() {
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.columns(
                mode: .grid, width: 1400, reservedHorizontalSpace: 50
            ).count, 5
        )
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.columns(
                mode: .list, width: 1400, reservedHorizontalSpace: 36
            ).count, 2
        )
        XCTAssertEqual(ATHLTHLibraryResponsiveLayout.hubColumns(for: 1400).count, 4)
    }

    func testStageManagerAndLargeTextDoNotSquashCards() {
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.columns(
                mode: .list, width: 750, reservedHorizontalSpace: 36
            ).count, 1
        )
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.columns(
                mode: .grid, width: 1024, reservedHorizontalSpace: 50,
                accessibilityText: true
            ).count, 2
        )
    }

    func testFeaturedCardsSpanLandscapeWithoutOverflowingPhone() {
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.featuredCardWidth(
                for: 390, accessibilityText: false
            ), 246, accuracy: 0.01
        )
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.featuredCardWidth(
                for: 1400, accessibilityText: false
            ), 676, accuracy: 0.01
        )
        XCTAssertEqual(
            ATHLTHLibraryResponsiveLayout.featuredCardHeight(
                for: 676, accessibilityText: false
            ), 320, accuracy: 0.01
        )
    }
}
