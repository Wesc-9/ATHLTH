import CoreGraphics
import XCTest
@testable import ATHLTH

final class ATHLTHSideMenuLayoutPolicyTests: XCTestCase {
    func testTypicalIPhoneWidthsLeaveVisibleHomeSpace() {
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 375),
            215.625,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 393),
            225.975,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 440),
            253,
            accuracy: 0.01
        )
    }

    func testDrawerIsFifteenPercentWiderThanBefore() {
        for width: CGFloat in [280, 320, 375, 393, 440] {
            let drawerWidth = ATHLTHSideMenuLayoutPolicy.width(for: width)
            XCTAssertEqual(drawerWidth, width * 0.5 * 1.15, accuracy: 0.01)
        }
    }

    func testSmallScreensKeepSpaceForDismissTap() {
        for width: CGFloat in [280, 320, 375, 393, 440] {
            let drawerWidth = ATHLTHSideMenuLayoutPolicy.width(for: width)
            XCTAssertGreaterThanOrEqual(width - drawerWidth, width * 0.425 - 0.01)
            XCTAssertGreaterThanOrEqual(width - drawerWidth, 110)
        }
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

    func testInteractiveCloseTracksOnlyHorizontalLeftSwipes() {
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.interactiveOffset(
                for: CGSize(width: -55, height: 6)
            ),
            -55
        )
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.interactiveOffset(
                for: CGSize(width: -55, height: 80)
            ),
            0
        )
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.interactiveOffset(
                for: CGSize(width: 85, height: 0)
            ),
            0
        )
    }

    func testBadgePolicyDeduplicatesImportedChallengeInvites() {
        let counts = ATHLTHSideMenuBadgePolicy.counts(
            messageUnread: 3,
            messageRequests: 1,
            backendChallengeInvites: 2,
            importedChallengeInvites: 1,
            notificationUnread: 4,
            pendingWorkoutImports: 2
        )
        XCTAssertEqual(counts.inbox, 5)
        XCTAssertEqual(counts.notifications, 6)
        XCTAssertEqual(counts.total, 11)
    }

    func testBadgePolicyNeverProducesNegativeCounts() {
        let counts = ATHLTHSideMenuBadgePolicy.counts(
            messageUnread: 0,
            messageRequests: 0,
            backendChallengeInvites: 1,
            importedChallengeInvites: 3,
            notificationUnread: 0,
            pendingWorkoutImports: 0
        )
        XCTAssertEqual(counts.inbox, 0)
        XCTAssertEqual(counts.notifications, 0)
        XCTAssertEqual(counts.total, 0)
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
