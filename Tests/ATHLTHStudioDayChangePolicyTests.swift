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

    func testBrowsingWeeksDoesNotChangeSelectedDate() {
        var navigation = ATHLTHStudioDayChangePolicy.Navigation(date: monday, calendar: calendar)
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: monday)!
        navigation.browseWeek(1, calendar: calendar)
        XCTAssertEqual(navigation.displayedWeekDate, nextWeek)
        XCTAssertEqual(navigation.selectedDate, monday)
        navigation.browseWeek(1, calendar: calendar)
        XCTAssertEqual(navigation.displayedWeekDate, calendar.date(byAdding: .day, value: 14, to: monday))
        XCTAssertEqual(navigation.selectedDate, monday)
        navigation.browseWeek(-1, calendar: calendar)
        let wednesday = calendar.date(byAdding: .day, value: 2, to: nextWeek)!
        XCTAssertEqual(ATHLTHStudioDayChangePolicy.decision(current: navigation.selectedDate,
            proposed: wednesday, hasStartedWorkout: true, calendar: calendar), .confirmDraft)
        XCTAssertEqual(navigation.selectedDate, monday)
        navigation.selectDay(wednesday, calendar: calendar)
        XCTAssertEqual(navigation.selectedDate, wednesday)
        XCTAssertEqual(navigation.displayedWeekDate, wednesday)
    }

    func testActivityCountsUseWorkoutCategoriesAndExcludeRest() {
        func workout(_ kind: WorkoutKind, category: String? = nil) -> PlannedSession {
            var value = PlannedSession(id: UUID(), title: "Workout", kind: kind,
                scheduledStart: nil, durationMinutes: 20, targetDistanceKilometers: nil,
                targetPaceSecondsPerKilometer: nil, routeID: nil, exercises: [], notes: nil)
            value.workoutCategory = category
            return value
        }
        let counts = ATHLTHStudioDayChangePolicy.activityCounts(for: [
            workout(.strength), workout(.strength), workout(.running),
            workout(.custom, category: "cycling"), workout(.recovery, category: "rest_day")
        ])
        XCTAssertEqual(counts.map(\.type), [.strength, .running, .cycling])
        XCTAssertEqual(counts.map(\.count), [2, 1, 1])
        XCTAssertTrue(ATHLTHStudioDayChangePolicy.activityCounts(for: []).isEmpty)
    }

    @MainActor
    func testEmptyPlannerSelectsDayInAnotherWeekWithoutDraftPrompt() {
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
    func testStartedWorkoutKeepsDraftConfirmationForExplicitDaySelectionAcrossWeeks() {
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

    func testSaveButtonNamesSelectedWeekdayAndDate() {
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        XCTAssertEqual(ATHLTHStudioDayChangePolicy.addWorkoutTitle(
            for: monday, norwegian: true, calendar: calendar), "Legg til økt mandag 23. november")
        XCTAssertEqual(ATHLTHStudioDayChangePolicy.addWorkoutTitle(
            for: tuesday, norwegian: true, calendar: calendar), "Legg til økt tirsdag 24. november")
        XCTAssertEqual(ATHLTHStudioDayChangePolicy.addWorkoutTitle(
            for: tuesday, norwegian: false, calendar: calendar), "Add workout on Tuesday 24 November")
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
