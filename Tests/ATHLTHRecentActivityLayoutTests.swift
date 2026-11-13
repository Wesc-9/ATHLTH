import CoreGraphics
import XCTest
@testable import ATHLTH

final class ATHLTHRecentActivityLayoutTests: XCTestCase {
    func testIPhoneCardsUseFullWidthMediaAboveText() {
        for width: CGFloat in [280, 320, 375, 393, 440, 600] {
            XCTAssertFalse(
                ATHLTHRecentActivityLayoutPolicy.isHorizontal(
                    availableWidth: width
                )
            )
            XCTAssertEqual(
                ATHLTHRecentActivityLayoutPolicy.artworkWidth(
                    for: width, horizontal: false
                ),
                width,
                accuracy: 0.01
            )
            XCTAssertEqual(
                ATHLTHRecentActivityLayoutPolicy.artworkHeight(
                    horizontal: false
                ),
                170
            )
        }
    }

    func testWideIPadWindowsUseSideBySideLayout() {
        for width: CGFloat in [650, 768, 820, 1024] {
            XCTAssertTrue(
                ATHLTHRecentActivityLayoutPolicy.isHorizontal(
                    availableWidth: width
                )
            )
            XCTAssertEqual(
                ATHLTHRecentActivityLayoutPolicy.artworkWidth(
                    for: width, horizontal: true
                ),
                width * 0.43,
                accuracy: 0.01
            )
            XCTAssertGreaterThan(
                width - ATHLTHRecentActivityLayoutPolicy.artworkWidth(
                    for: width, horizontal: true
                ),
                width * 0.5
            )
        }
    }

    func testStageManagerNarrowWindowAndAccessibilityKeepVerticalLayout() {
        XCTAssertFalse(
            ATHLTHRecentActivityLayoutPolicy.isHorizontal(
                availableWidth: 580
            )
        )
        XCTAssertFalse(
            ATHLTHRecentActivityLayoutPolicy.isHorizontal(
                availableWidth: 820, accessibilityText: true
            )
        )
    }
}
