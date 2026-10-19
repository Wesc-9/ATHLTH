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
    func testTappedWorkoutOpensItsOwnPlanOrStandaloneDetail() {
        let scheduled = PlannedSession(
            id: UUID(),
            title: "Styrke bein",
            kind: .strength,
            scheduledStart: date(2026, 10, 14),
            exercises: []
        )
        let standalone = PlannedSession(
            id: UUID(),
            title: "Ekstra løpetur",
            kind: .running,
            scheduledStart: date(2026, 10, 14),
            exercises: []
        )
        let plan = TrainingPlan(
            id: UUID(),
            ownerID: UUID(),
            title: "Aktiv treningsplan",
            summary: "",
            visibility: .privateOnly,
            version: 1,
            weeks: [
                TrainingPlanWeek(
                    id: UUID(),
                    weekNumber: 1,
                    title: "Uke 1",
                    days: [
                        TrainingPlanDay(
                            id: UUID(),
                            dayIndex: 1,
                            title: "Onsdag",
                            sessions: [scheduled]
                        )
                    ]
                )
            ],
            tags: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(
            HomeWeeklyProgressCalendar.containingPlanID(
                for: scheduled, in: plan
            ), plan.id
        )
        XCTAssertNil(
            HomeWeeklyProgressCalendar.containingPlanID(
                for: standalone, in: plan
            )
        )
        XCTAssertNil(
            HomeWeeklyProgressCalendar.containingPlanID(
                for: scheduled, in: nil
            )
        )
    }


    func testTodayCalendarIncludesStandaloneWithoutAnActivePlan() {
        let today = date(2026, 10, 19)
        let scheduled = PlannedSession(
            id: UUID(), title: "4 × 4 intervaller", kind: .running,
            scheduledStart: today, exercises: []
        )
        let tomorrow = PlannedSession(
            id: UUID(), title: "Restitusjonsløp", kind: .running,
            scheduledStart: date(2026, 10, 20), exercises: []
        )

        let visible = HomeTodayCalendarSchedule.workouts(
            plan: nil, standalone: [tomorrow, scheduled],
            on: today, calendar: calendar
        )

        XCTAssertEqual(visible.map(\.id), [scheduled.id])
    }

    func testTodayCalendarMergesPlanAndStandaloneChronologically() {
        let day = date(2026, 10, 19)
        let early = day.addingTimeInterval(-60 * 60)
        let late = day.addingTimeInterval(60 * 60)
        let planned = PlannedSession(
            id: UUID(), title: "Styrke", kind: .strength,
            scheduledStart: late, exercises: []
        )
        let extra = PlannedSession(
            id: UUID(), title: "Intervaller", kind: .running,
            scheduledStart: early, exercises: []
        )
        let plan = TrainingPlan(
            id: UUID(), ownerID: UUID(), title: "Plan", summary: "",
            visibility: .privateOnly, version: 1,
            weeks: [TrainingPlanWeek(
                id: UUID(), weekNumber: 1, title: "Uke 1",
                days: [TrainingPlanDay(
                    id: UUID(), dayIndex: 1, title: "Mandag",
                    sessions: [planned]
                )]
            )],
            tags: [], createdAt: day, updatedAt: day,
            startDate: calendar.startOfDay(for: day)
        )

        let visible = HomeTodayCalendarSchedule.workouts(
            plan: plan, standalone: [extra],
            on: day, calendar: calendar
        )

        XCTAssertEqual(visible.map(\.id), [extra.id, planned.id])
        XCTAssertNil(
            HomeWeeklyProgressCalendar.containingPlanID(
                for: extra, in: plan
            )
        )
        XCTAssertEqual(
            HomeWeeklyProgressCalendar.containingPlanID(
                for: planned, in: plan
            ), plan.id
        )
    }

    func testTodayCalendarDoesNotDuplicateAWorkoutSavedInBothSources() {
        let day = date(2026, 10, 19)
        let original = PlannedSession(
            id: UUID(), title: "Intervaller", kind: .running,
            scheduledStart: day, exercises: []
        )
        var revised = original
        revised.title = "Intervaller (oppdatert)"
        let plan = TrainingPlan(
            id: UUID(), ownerID: UUID(), title: "Plan", summary: "",
            visibility: .privateOnly, version: 1,
            weeks: [TrainingPlanWeek(
                id: UUID(), weekNumber: 1, title: "Uke 1",
                days: [TrainingPlanDay(
                    id: UUID(), dayIndex: 1, title: "Mandag",
                    sessions: [original]
                )]
            )],
            tags: [], createdAt: day, updatedAt: day,
            startDate: calendar.startOfDay(for: day)
        )

        let visible = HomeTodayCalendarSchedule.workouts(
            plan: plan, standalone: [revised],
            on: day, calendar: calendar
        )

        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.title, "Intervaller (oppdatert)")
    }

}
