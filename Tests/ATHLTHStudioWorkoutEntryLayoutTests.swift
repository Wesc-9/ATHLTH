import CoreGraphics
import Foundation
import XCTest
@testable import ATHLTH

/// Only presentation sizes change on iPad; the activity and draft workflow
/// must always use the existing shared builder and its iPhone catalog.
@MainActor
final class ATHLTHStudioWorkoutEntryLayoutTests: XCTestCase {
    func testRegularLandscapeUsesThreeBalancedActivityColumns() {
        XCTAssertEqual(
            ATHLTHStudioWorkoutEntryLayoutPolicy.columns(for: 930), 3
        )
        XCTAssertEqual(
            ATHLTHStudioWorkoutEntryLayoutPolicy.columns(for: 760), 2
        )
        XCTAssertEqual(
            ATHLTHStudioWorkoutEntryLayoutPolicy.columns(for: 410), 1
        )
    }

    func testStageManagerAndAccessibilityUseReadableLayout() {
        XCTAssertEqual(
            ATHLTHStudioWorkoutEntryLayoutPolicy.columns(
                for: 1_300, accessibility: true
            ), 1
        )
        XCTAssertFalse(
            ATHLTHStudioWorkoutEntryLayoutPolicy.showsContextPanel(
                for: 1_500, accessibility: true
            )
        )
        XCTAssertFalse(
            ATHLTHStudioWorkoutEntryLayoutPolicy.showsContextPanel(for: 930)
        )
        XCTAssertTrue(
            ATHLTHStudioWorkoutEntryLayoutPolicy.showsContextPanel(for: 1_100)
        )
        XCTAssertGreaterThanOrEqual(
            ATHLTHStudioWorkoutEntryLayoutPolicy.tileHeight(
                for: 450, accessibility: true
            ), 200
        )
    }

    func testIPhoneActivityTypesRemainTheOnlySixIPadChoices() {
        XCTAssertEqual(
            ATHLTHPlannedWorkoutType.defaultOrder,
            [.strength, .running, .walking, .cycling, .mobility, .custom]
        )
        XCTAssertEqual(Set(ATHLTHPlannedWorkoutType.defaultOrder).count, 6)
        for type in ATHLTHPlannedWorkoutType.defaultOrder {
            XCTAssertFalse(type.imageName.isEmpty)
            XCTAssertFalse(type.symbol.isEmpty)
        }
    }

    func testSidebarUsesOneNativeControllerAndDoesNotNeedCustomHamburger() {
        XCTAssertEqual(ATHLTHStudioSidebarLayoutPolicy.fixedWidth, 280)
    }
}
