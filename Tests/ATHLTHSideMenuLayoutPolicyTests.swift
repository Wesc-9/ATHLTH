import CoreGraphics
import XCTest
@testable import ATHLTH

final class ATHLTHSideMenuLayoutPolicyTests: XCTestCase {
    func testTypicalIPhoneWidthsLeaveVisibleHomeSpace() {
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 375),
            285,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 393),
            298.68,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 440),
            320,
            accuracy: 0.01
        )
    }

    func testSmallScreensKeepSpaceForDismissTap() {
        XCTAssertLessThanOrEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 320),
            264
        )
        XCTAssertLessThanOrEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 280),
            224
        )
    }

    func testLeftSwipeClosesWithoutCapturingVerticalScroll() {
        XCTAssertTrue(
            ATHLTHSideMenuLayoutPolicy.shouldDismiss(
                translation: CGSize(width: -90, height: 8)
            )
        )
        XCTAssertFalse(
            ATHLTHSideMenuLayoutPolicy.shouldDismiss(
                translation: CGSize(width: 100, height: 0)
            )
        )
        XCTAssertFalse(
            ATHLTHSideMenuLayoutPolicy.shouldDismiss(
                translation: CGSize(width: -90, height: 100)
            )
        )
        XCTAssertFalse(
            ATHLTHSideMenuLayoutPolicy.shouldDismiss(
                translation: CGSize(width: -25, height: 1)
            )
        )
    }
}

final class ATHLTHStudioInboxPanelGesturePolicyTests: XCTestCase {
    func testOpeningRequiresDeliberateLeftSwipe() {
        XCTAssertTrue(ATHLTHStudioInboxPanelGesturePolicy.shouldOpen(
            translation: CGSize(width: -85, height: 14)
        ))
        XCTAssertFalse(ATHLTHStudioInboxPanelGesturePolicy.shouldOpen(
            translation: CGSize(width: 85, height: 0)
        ))
        XCTAssertFalse(ATHLTHStudioInboxPanelGesturePolicy.shouldOpen(
            translation: CGSize(width: -25, height: 0)
        ))
        XCTAssertFalse(ATHLTHStudioInboxPanelGesturePolicy.shouldOpen(
            translation: CGSize(width: -90, height: 90)
        ))
    }

    func testClosingRequiresDeliberateRightSwipeOnPanelHeader() {
        XCTAssertTrue(ATHLTHStudioInboxPanelGesturePolicy.shouldClose(
            translation: CGSize(width: 105, height: 10)
        ))
        XCTAssertFalse(ATHLTHStudioInboxPanelGesturePolicy.shouldClose(
            translation: CGSize(width: -120, height: 0)
        ))
        XCTAssertFalse(ATHLTHStudioInboxPanelGesturePolicy.shouldClose(
            translation: CGSize(width: 60, height: 0)
        ))
        XCTAssertFalse(ATHLTHStudioInboxPanelGesturePolicy.shouldClose(
            translation: CGSize(width: 110, height: 95)
        ))
    }
}
