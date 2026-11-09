import XCTest
@testable import ATHLTH

final class ATHLTHStudioDayCompletionPolicyTests: XCTestCase {
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
