import SwiftUI
import XCTest
@testable import ATHLTH

final class ATHLTHStudioAdaptiveWorkspaceTests: XCTestCase {
    func testSplitLeavesEnoughRoomForWorkoutEditor() {
        let width = ATHLTHStudioWorkspaceLayout.planWidth(
            totalWidth: 950,
            fraction: 0.8
        )
        XCTAssertEqual(width, 406, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(950 - width - 14, 530)
    }

    func testPlanColumnDoesNotShrinkBelowUsableWidth() {
        let width = ATHLTHStudioWorkspaceLayout.planWidth(
            totalWidth: 1180,
            fraction: 0.1
        )
        XCTAssertEqual(width, 275, accuracy: 0.01)
    }

    func testDragPersistsAndClampsPreferredFraction() {
        let larger = ATHLTHStudioWorkspaceLayout.persistedFraction(
            totalWidth: 1200,
            currentFraction: 0.32,
            dragDelta: 180
        )
        XCTAssertEqual(larger, 0.47, accuracy: 0.001)

        XCTAssertEqual(
            ATHLTHStudioWorkspaceLayout.persistedFraction(
                totalWidth: 1200,
                currentFraction: 0.50,
                dragDelta: 400
            ),
            0.53,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ATHLTHStudioWorkspaceLayout.persistedFraction(
                totalWidth: 1200,
                currentFraction: 0.32,
                dragDelta: -300
            ),
            0.26,
            accuracy: 0.001
        )
    }
}
