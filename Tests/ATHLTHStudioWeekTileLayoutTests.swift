import SwiftUI
import XCTest
@testable import ATHLTH

final class ATHLTHStudioWeekTileLayoutTests: XCTestCase {
    func testAllSevenDaysFitWhenIPadDetailIsWide() {
        for width: CGFloat in [730, 820, 1080, 1300, 1500] {
            let tile = ATHLTHStudioWeekTileLayout.tileWidth(
                viewport: width, accessibilityText: false
            )
            let outerInset: CGFloat = 44
            let total = outerInset + 40 + 6 * 8 + tile * 7
            XCTAssertLessThanOrEqual(total, width + 0.01)
        }
    }

    func testNarrowStageManagerWindowsScrollInsteadOfSqueezingDayText() {
        let tile = ATHLTHStudioWeekTileLayout.tileWidth(
            viewport: 480, accessibilityText: false
        )
        XCTAssertEqual(tile, 88)
    }

    func testLargeTypeUsesLegibleMinimumInsteadOfClippingLabels() {
        let tile = ATHLTHStudioWeekTileLayout.tileWidth(
            viewport: 680, accessibilityText: true
        )
        XCTAssertGreaterThanOrEqual(tile, 88)
    }
}
