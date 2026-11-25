import CoreGraphics
import SwiftUI
import XCTest
@testable import ATHLTH

final class ATHLTHSideMenuLayoutPolicyTests: XCTestCase {
    func testTypicalIPhoneWidthsLeaveVisibleHomeSpace() {
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 375),
            225,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 393),
            235.8,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 440),
            264,
            accuracy: 0.01
        )
    }

    func testDrawerMatchesRefinedSixtyPercentLayout() {
        for width: CGFloat in [280, 320, 375, 393, 440] {
            let drawerWidth = ATHLTHSideMenuLayoutPolicy.width(for: width)
            XCTAssertEqual(drawerWidth, width * 0.60, accuracy: 0.01)
            XCTAssertLessThanOrEqual(drawerWidth, 280)
        }
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 900), 280, accuracy: 0.01
        )
        XCTAssertEqual(ATHLTHSideMenuLayoutPolicy.width(for: 0), 0)
    }

    func testSmallScreensKeepSpaceForDismissTap() {
        for width: CGFloat in [280, 320, 375, 393, 440] {
            let drawerWidth = ATHLTHSideMenuLayoutPolicy.width(for: width)
            XCTAssertGreaterThanOrEqual(width - drawerWidth, width * 0.40 - 0.01)
            XCTAssertGreaterThanOrEqual(width - drawerWidth, 110)
        }
    }

    func testAccessibilityTypographyGetsExtraWidthAndDismissSpace() {
        for width: CGFloat in [280, 320, 375, 393, 440] {
            let regular = ATHLTHSideMenuLayoutPolicy.width(for: width)
            let accessible = ATHLTHSideMenuLayoutPolicy.width(
                for: width, accessibilitySize: true
            )
            XCTAssertGreaterThan(accessible, regular)
            XCTAssertLessThanOrEqual(accessible, width * 0.78 + 0.01)
            XCTAssertGreaterThanOrEqual(width - accessible, 60)
        }
        XCTAssertEqual(
            ATHLTHSideMenuLayoutPolicy.width(for: 900, accessibilitySize: true),
            350, accuracy: 0.01
        )
    }

    func testGlobalSearchHasExplicitPeopleAndExerciseFilters() {
        XCTAssertTrue(ATHLTHGlobalSearchScope.allCases.contains(.users))
        XCTAssertTrue(ATHLTHGlobalSearchScope.allCases.contains(.exercises))
        XCTAssertTrue(ATHLTHGlobalSearchScope.allCases.contains(.routes))
        XCTAssertEqual(ATHLTHGlobalSearchScope.exercises.localizedTitle.isEmpty, false)
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

final class ATHLTHiPadStudioSidebarPolicyTests: XCTestCase {
    func testSidebarWidthStaysAtScreenshotSize() {
        // The expanded Studio sidebar on regular-width iPads is 280pt.
        XCTAssertEqual(ATHLTHStudioSidebarLayoutPolicy.fixedWidth, 280, accuracy: 0.01)
    }

    func testOnlyExplicitMenuToggleChangesVisibility() {
        XCTAssertEqual(
            ATHLTHStudioSidebarLayoutPolicy.toggled(.all),
            .detailOnly
        )
        XCTAssertEqual(
            ATHLTHStudioSidebarLayoutPolicy.toggled(.detailOnly),
            .all
        )
    }

    func testTogglingTwiceRestoresOriginalVisibility() {
        for visibility: NavigationSplitViewVisibility in [.all, .detailOnly] {
            XCTAssertEqual(
                ATHLTHStudioSidebarLayoutPolicy.toggled(
                    ATHLTHStudioSidebarLayoutPolicy.toggled(visibility)
                ),
                visibility
            )
        }
    }
}
