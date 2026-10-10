import Foundation
import XCTest
@testable import ATHLTH

final class HomeWeeklyProgressCalendarTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        calendar.firstWeekday = 2 // Monday
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: 12
        ))!
    }

    func testWeekPagerMovesExactlyOneCalendarWeekInEitherDirection() {
        let reference = date(2026, 10, 23)
        let current = HomeWeeklyProgressCalendar.weekInterval(
            offset: 0, referenceDate: reference, calendar: calendar
        )
        let next = HomeWeeklyProgressCalendar.weekInterval(
            offset: 1, referenceDate: reference, calendar: calendar
        )
        let previous = HomeWeeklyProgressCalendar.weekInterval(
            offset: -1, referenceDate: reference, calendar: calendar
        )

        // Oslo switches to winter time during this week. Calendar-day
        // navigation must still show Monday-to-Monday without 1-hour drift.
        XCTAssertEqual(calendar.component(.weekday, from: current.start), 2)
        XCTAssertEqual(calendar.component(.weekday, from: next.start), 2)
        XCTAssertEqual(calendar.component(.weekday, from: previous.start), 2)
        XCTAssertEqual(
            calendar.dateComponents([.day], from: current.start, to: next.start).day,
            7
        )
        XCTAssertEqual(
            calendar.dateComponents([.day], from: previous.start, to: current.start).day,
            7
        )
        XCTAssertEqual(current.end, next.start)
        XCTAssertEqual(
            HomeWeeklyProgressCalendar.weekInterval(
                offset: 0, referenceDate: reference, calendar: calendar
            ).start, current.start
        )
    }

    func testPlanStartingWednesdayKeepsWeekAndDayIndexesAligned() {
        let first = date(2026, 4, 8) // Wednesday
        let onMonday = date(2026, 4, 13)
        let nextWednesday = date(2026, 4, 15)
        let previousTuesday = date(2026, 4, 7)

        let initial = HomeWeeklyProgressCalendar.planPosition(
            for: first, startDate: first, calendar: calendar
        )
        XCTAssertEqual(initial?.weekIndex, 0)
        XCTAssertEqual(initial?.dayIndex, 1)

        let monday = HomeWeeklyProgressCalendar.planPosition(
            for: onMonday, startDate: first, calendar: calendar
        )
        XCTAssertEqual(monday?.weekIndex, 0)
        XCTAssertEqual(monday?.dayIndex, 6)

        let later = HomeWeeklyProgressCalendar.planPosition(
            for: nextWednesday, startDate: first, calendar: calendar
        )
        XCTAssertEqual(later?.weekIndex, 1)
        XCTAssertEqual(later?.dayIndex, 1)

        XCTAssertNil(HomeWeeklyProgressCalendar.planPosition(
            for: previousTuesday, startDate: first, calendar: calendar
        ))
    }

    func testCompletedWorkoutTypesUseNorwegianLabels() {
        XCTAssertEqual(
            HomeCompletedWorkoutPresentation.title(for: .running, norwegian: true),
            "Løping"
        )
        XCTAssertEqual(
            HomeCompletedWorkoutPresentation.title(for: .strength, norwegian: true),
            "Styrke"
        )
        XCTAssertEqual(
            HomeCompletedWorkoutPresentation.title(for: .coreTraining, norwegian: true),
            "Kjernetrening"
        )
        XCTAssertEqual(
            HomeCompletedWorkoutPresentation.title(for: .running, norwegian: false),
            "Running"
        )
    }

    func testStandaloneShortcutAllowsOnlyTodayAndFutureDays() {
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 10, hour: 23, minute: 59
        ))!

        XCTAssertFalse(HomeWeeklyProgressCalendar.canScheduleStandalone(
            on: date(2026, 10, 9), asOf: now, calendar: calendar
        ))
        XCTAssertTrue(HomeWeeklyProgressCalendar.canScheduleStandalone(
            on: date(2026, 10, 10), asOf: now, calendar: calendar
        ))
        XCTAssertTrue(HomeWeeklyProgressCalendar.canScheduleStandalone(
            on: date(2026, 10, 14), asOf: now, calendar: calendar
        ))
    }

    func testWeekPagerWorksForUnscheduledFutureWeeks() {
        let reference = date(2026, 10, 9)
        let interval = HomeWeeklyProgressCalendar.weekInterval(
            offset: 15, referenceDate: reference, calendar: calendar
        )
        XCTAssertEqual(
            calendar.dateComponents(
                [.weekOfYear],
                from: HomeWeeklyProgressCalendar.weekInterval(
                    offset: 0, referenceDate: reference, calendar: calendar
                ).start,
                to: interval.start
            ).weekOfYear,
            15
        )
    }
}
