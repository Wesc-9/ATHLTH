import XCTest
@testable import ATHLTH

final class ATHLTHStudioDayCompletionPolicyTests: XCTestCase {
    func testFinishedSessionsLeavePendingGridWithoutReordering() {
        let result = ATHLTHStudioDayCompletionPolicy.partition([1, 2, 3, 4]) {
            $0 == 1 || $0 == 3
        }
        XCTAssertEqual(result.pending, [2, 4])
        XCTAssertEqual(result.finished, [1, 3])
    }

    func testAllFinishedLeavesNoHeroCards() {
        let result = ATHLTHStudioDayCompletionPolicy.partition([1, 2]) { _ in true }
        XCTAssertTrue(result.pending.isEmpty)
        XCTAssertEqual(result.finished, [1, 2])
    }

    func testWorkoutGridFitsTwoCardsOnWideIPadAndAdaptsToNarrowWindow() {
        let width = ATHLTHStudioDayWorkoutLayout.contentWidth(viewport: 1366, accessibilityText: false)
        XCTAssertEqual(ATHLTHStudioDayWorkoutLayout.columns(contentWidth: width, count: 3, accessibilityText: false), 2)
        XCTAssertEqual(ATHLTHStudioDayWorkoutLayout.columns(contentWidth: width, count: 1, accessibilityText: false), 1)
        XCTAssertEqual(ATHLTHStudioDayWorkoutLayout.columns(contentWidth: 500, count: 2, accessibilityText: false), 1)
        XCTAssertEqual(ATHLTHStudioDayWorkoutLayout.columns(contentWidth: width, count: 2, accessibilityText: true), 1)
    }

    func testEmptyDayIsNotCompleted() {
        XCTAssertFalse(
            ATHLTHStudioDayCompletionPolicy.allPlannedCompleted(
                [Int](), isCompleted: { _ in true }
            )
        )
    }

    func testOnlyFirstOfTwoSessionsCompletedDoesNotCompleteDay() {
        XCTAssertFalse(
            ATHLTHStudioDayCompletionPolicy.allPlannedCompleted(
                [1, 2], isCompleted: { $0 == 1 }
            )
        )
    }

    func testAllPlannedSessionsCompleteMarksDayComplete() {
        XCTAssertTrue(
            ATHLTHStudioDayCompletionPolicy.allPlannedCompleted(
                [1, 2, 3], isCompleted: { $0 <= 3 }
            )
        )
    }

    func testAllButOneCompletedDoesNotCreateFalseCheckmark() {
        XCTAssertFalse(
            ATHLTHStudioDayCompletionPolicy.allPlannedCompleted(
                [1, 2, 3], isCompleted: { $0 != 2 }
            )
        )
    }
}
