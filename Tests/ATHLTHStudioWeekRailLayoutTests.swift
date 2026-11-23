import XCTest
@testable import ATHLTH

final class ATHLTHStudioWeekRailLayoutTests: XCTestCase {
    func testSevenDayCardsAlwaysFitRegularHeightWithoutScrolling() {
        for windowHeight: CGFloat in [600, 700, 768, 900, 1056, 1200] {
            let railHeight = windowHeight - 66 // Planner header minimum height.
            let cardHeight = ATHLTHStudioWeekRailLayout.dayHeight(
                for: railHeight
            )
            let occupied =
                2 * ATHLTHStudioWeekRailLayout.verticalInset +
                ATHLTHStudioWeekRailLayout.headerHeight +
                ATHLTHStudioWeekRailLayout.sectionSpacing +
                6 * ATHLTHStudioWeekRailLayout.daySpacing +
                7 * cardHeight
            XCTAssertLessThanOrEqual(
                occupied, railHeight + 0.001,
                "Seven day tiles must fit with their week header at height \(windowHeight)"
            )
            XCTAssertGreaterThanOrEqual(cardHeight, 44)
            XCTAssertLessThanOrEqual(cardHeight, 99)
        }
    }

    func testCompactGridReplacesRailInShortOrNarrowWindows() {
        XCTAssertTrue(ATHLTHStudioWeekRailLayout.useVerticalRail(
            width: 1024, height: 768
        ))
        XCTAssertFalse(ATHLTHStudioWeekRailLayout.useVerticalRail(
            width: 650, height: 768
        ))
        XCTAssertFalse(ATHLTHStudioWeekRailLayout.useVerticalRail(
            width: 1024, height: 520
        ))
    }

    func testRailWidthDoesNotTakeOverEditor() {
        for width: CGFloat in [680, 900, 1024, 1366] {
            let rail = ATHLTHStudioWeekRailLayout.width(in: width)
            XCTAssertLessThanOrEqual(rail, 256)
            XCTAssertGreaterThan(width - rail, 450)
        }
    }

    func testISOWeekLabelMatchesNorwegianMondayAtYearBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3600)!
        let monday = calendar.date(
            from: DateComponents(year: 2026, month: 12, day: 28, hour: 12)
        )!
        XCTAssertEqual(
            ATHLTHStudioWeekRailLayout.weekNumber(
                for: monday, timeZone: calendar.timeZone
            ),
            53
        )
    }
}
