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

    func testSelectedDayUsesCalendarDayNotTimeOfDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 22)))
        let today = calendar.startOfDay(for: now)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        XCTAssertTrue(ATHLTHStudioDayCardPolicy.isPast(yesterday, now: now, calendar: calendar))
        XCTAssertFalse(ATHLTHStudioDayCardPolicy.isPast(today, now: now, calendar: calendar))
        XCTAssertFalse(ATHLTHStudioDayCardPolicy.isPast(tomorrow, now: now, calendar: calendar))
    }

    func testDayCardUsesSharedNormalHeightButAllowsAccessibilityExpansion() {
        XCTAssertEqual(ATHLTHStudioDayCardPolicy.bodyHeight(accessibilityText: false),
                       ATHLTHStudioDayCardPolicy.bodyHeight)
        XCTAssertNil(ATHLTHStudioDayCardPolicy.bodyHeight(accessibilityText: true))
    }
}
