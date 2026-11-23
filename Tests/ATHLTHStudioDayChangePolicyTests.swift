import XCTest
@testable import ATHLTH

final class ATHLTHStudioDayChangePolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var monday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))!
    }

    @MainActor
    func testEmptyPlannerChangesDaysWithoutDraftPrompt() {
        let nextDay = calendar.date(byAdding: .day, value: 1, to: monday)!
        XCTAssertEqual(
            ATHLTHStudioDayChangePolicy.decision(
                current: monday,
                proposed: nextDay,
                hasStartedWorkout: false,
                calendar: calendar
            ),
            .switchImmediately
        )
    }

    @MainActor
    func testEmptyPlannerChangesWeekWithoutDraftPrompt() {
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: monday)!
        XCTAssertEqual(
            ATHLTHStudioDayChangePolicy.decision(
                current: monday,
                proposed: nextWeek,
                hasStartedWorkout: false,
                calendar: calendar
            ),
            .switchImmediately
        )
    }

    @MainActor
    func testStartedWorkoutKeepsDraftConfirmationForDayAndWeek() {
        for days in [1, 7] {
            let proposed = calendar.date(byAdding: .day, value: days, to: monday)!
            XCTAssertEqual(
                ATHLTHStudioDayChangePolicy.decision(
                    current: monday,
                    proposed: proposed,
                    hasStartedWorkout: true,
                    calendar: calendar
                ),
                .confirmDraft
            )
        }
    }

    func testClockSelectionNeverMovesTheSelectedTrainingDay() {
        let selected = calendar.date(byAdding: .day, value: 1, to: monday)!
        let differentDay = calendar.date(bySettingHour: 7, minute: 35, second: 42, of: monday)!
        let normalized = ATHLTHStudioDayChangePolicy.timeOnDay(differentDay, day: selected, calendar: calendar)
        XCTAssertTrue(calendar.isDate(normalized, inSameDayAs: selected))
        XCTAssertEqual(calendar.component(.hour, from: normalized), 7)
        XCTAssertEqual(calendar.component(.minute, from: normalized), 35)
        XCTAssertEqual(calendar.component(.second, from: normalized), 0)
    }

    @MainActor
    func testSelectingSameDayNeverPrompts() {
        let laterOnSameDay = calendar.date(byAdding: .hour, value: 6, to: monday)!
        for hasStartedWorkout in [false, true] {
            XCTAssertEqual(
                ATHLTHStudioDayChangePolicy.decision(
                    current: monday,
                    proposed: laterOnSameDay,
                    hasStartedWorkout: hasStartedWorkout,
                    calendar: calendar
                ),
                .unchanged
            )
        }
    }
}
