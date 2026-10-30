import CoreGraphics
import XCTest
@testable import ATHLTH

final class ATHLTHHomeToolbarDragPolicyTests: XCTestCase {
    func testPullLeftExpandsCollapsedToolbar() {
        XCTAssertTrue(ATHLTHHomeToolbarDragPolicy.expanded(
            currentlyExpanded: false,
            translation: CGSize(width: -70, height: 4)
        ))
    }

    func testPushRightCollapsesExpandedToolbar() {
        XCTAssertFalse(ATHLTHHomeToolbarDragPolicy.expanded(
            currentlyExpanded: true,
            translation: CGSize(width: 65, height: 2)
        ))
    }

    func testSmallAndVerticalDragsDoNotToggleOrInterceptScroll() {
        XCTAssertTrue(ATHLTHHomeToolbarDragPolicy.expanded(
            currentlyExpanded: true,
            translation: CGSize(width: -22, height: 1)
        ))
        XCTAssertFalse(ATHLTHHomeToolbarDragPolicy.expanded(
            currentlyExpanded: false,
            translation: CGSize(width: -42, height: 75)
        ))
        XCTAssertTrue(ATHLTHHomeToolbarDragPolicy.expanded(
            currentlyExpanded: true,
            translation: CGSize(width: 40, height: 40)
        ))
    }
}
