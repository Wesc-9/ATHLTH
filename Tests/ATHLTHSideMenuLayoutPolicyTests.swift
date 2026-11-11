import CoreGraphics
import XCTest
@testable import ATHLTH

final class ATHLTHSideMenuLayoutPolicyTests: XCTestCase {
    func testTypicalIPhoneWidthsLeaveVisibleHomeSpace() {
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 375),
            315,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 393),
            330.12,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 440),
            369.6,
            accuracy: 0.01
        )
    }

    func testRestoredDrawerIsWiderWithoutCoveringEntireScreen() {
        for width: CGFloat in [280, 320, 375, 393, 440] {
            let drawerWidth = ATHLTHSideMenuLayoutPolicy.width(for: width)
            XCTAssertGreaterThan(drawerWidth, 0)
            XCTAssertLessThanOrEqual(drawerWidth, width - 34)
        }
    }

    func testSmallScreensKeepSpaceForDismissTap() {
        XCTAssertLessThanOrEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 320),
            286
        )
        XCTAssertLessThanOrEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 280),
            246
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
