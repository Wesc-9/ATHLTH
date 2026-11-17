import XCTest
@testable import ATHLTH

final class ATHLTHTrainTodayDailyAdvicePolicyTests: XCTestCase {
    func testHistoryAdviceAppearsOnlyWhenTodayIsOpen() {
        XCTAssertTrue(ATHLTHTrainTodayDailyAdvicePolicy.isVisible(
            scheduledItemCount: 0,
            hasRecordedWorkoutToday: false,
            hasActiveWorkout: false,
            hasPersonalizedAdvice: true
        ))
        XCTAssertFalse(ATHLTHTrainTodayDailyAdvicePolicy.isVisible(
            scheduledItemCount: 0,
            hasRecordedWorkoutToday: false,
            hasActiveWorkout: false,
            hasPersonalizedAdvice: false
        ))
    }

    func testAnyCalendarItemIncludingRestDaySuppressesAdvice() {
        for count in [1, 2, 5] {
            XCTAssertFalse(ATHLTHTrainTodayDailyAdvicePolicy.isVisible(
                scheduledItemCount: count,
                hasRecordedWorkoutToday: false,
                hasActiveWorkout: false,
                hasPersonalizedAdvice: true
            ))
        }
    }

    func testRecordedOrLiveSessionSuppressesAdvice() {
        XCTAssertFalse(ATHLTHTrainTodayDailyAdvicePolicy.isVisible(
            scheduledItemCount: 0,
            hasRecordedWorkoutToday: true,
            hasActiveWorkout: false,
            hasPersonalizedAdvice: true
        ))
        XCTAssertFalse(ATHLTHTrainTodayDailyAdvicePolicy.isVisible(
            scheduledItemCount: 0,
            hasRecordedWorkoutToday: false,
            hasActiveWorkout: true,
            hasPersonalizedAdvice: true
        ))
    }
}
