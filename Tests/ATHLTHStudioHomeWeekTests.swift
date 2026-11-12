import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHStudioHomeWeekTests: XCTestCase {
    private func session(
        _ name: String,
        on date: Date?,
        kind: WorkoutKind = .running
    ) -> PlannedSession {
        PlannedSession(
            id: UUID(), title: name, kind: kind, scheduledStart: date,
            durationMinutes: 45, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: nil
        )
    }

    @MainActor
    func testMondayToSundayShowsPlanAndStandaloneWithoutDoubleCounting() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "ATHLTHStudioHomeWeek.\(UUID().uuidString)")
        )
        let store = AppSessionStore(defaults: defaults)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let mondayOffset = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -mondayOffset, to: today)
        )
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Week", summary: "", weekCount: 1, startDate: monday
        ))
        let planned = session("Intervals", on: nil)
        store.addSession(planned, toDay: plan.weeks[0].days[2].id, inPlan: plan.id)
        let refreshed = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let saturday = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 5, to: monday)
        )
        let extra = session("Walk", on: saturday, kind: .walking)

        let week = ATHLTHStudioHomeWeek.make(
            plans: [refreshed, refreshed],
            standalone: [extra, extra],
            recorded: [],
            now: today
        )

        XCTAssertEqual(week.days.count, 7)
        XCTAssertEqual(week.plannedCount, 2)
        XCTAssertEqual(week.recordedCount, 0)
        XCTAssertEqual(week.days[2].planned.first?.planID, plan.id)
        XCTAssertEqual(week.days[5].planned.first?.workout.id, extra.id)
        XCTAssertNil(week.days[5].planned.first?.planID)
        XCTAssertEqual(week.plannedMinutes, 90)
    }

    @MainActor
    func testPausedPlansAreNotShownInWeek() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "ATHLTHStudioHomeWeek.\(UUID().uuidString)")
        )
        let store = AppSessionStore(defaults: defaults)
        let today = Calendar.current.startOfDay(for: .now)
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Paused", summary: "", weekCount: 1, startDate: today
        ))
        store.addSession(
            session("Rested", on: today), toDay: plan.weeks[0].days[0].id,
            inPlan: plan.id
        )
        let stored = try XCTUnwrap(store.trainingPlan(withID: plan.id))

        XCTAssertEqual(ATHLTHStudioHomeWeek.make(
            plans: [stored], standalone: [], recorded: [],
            pausedPlanIDs: [stored.id], now: today
        ).plannedCount, 0)
    }

    func testNextWeekNavigationFindsItsOwnScheduledWorkout() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let wednesday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 4, hour: 12
        )))
        let followingWednesday = ATHLTHStudioHomeWeek.shiftedWeek(
            from: wednesday, offset: 1, calendar: calendar
        )
        let nextWeekWorkout = session("Next week run", on: followingWednesday)
        let current = ATHLTHStudioHomeWeek.make(
            plans: [], standalone: [nextWeekWorkout],
            recorded: [], now: wednesday, calendar: calendar
        )
        let next = ATHLTHStudioHomeWeek.make(
            plans: [], standalone: [nextWeekWorkout],
            recorded: [], now: followingWednesday, calendar: calendar
        )
        XCTAssertEqual(current.plannedCount, 0)
        XCTAssertEqual(next.plannedCount, 1)
        XCTAssertEqual(next.days[2].planned.first?.workout.id,
                       nextWeekWorkout.id)
        XCTAssertEqual(calendar.component(.weekday, from: next.days[0].date), 2)
    }

    func testWeekArrowsPreserveCalendarDateOverOsloDst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let before = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 21, hour: 12
        )))
        let next = ATHLTHStudioHomeWeek.shiftedWeek(
            from: before, offset: 1, calendar: calendar
        )
        XCTAssertEqual(calendar.component(.day, from: next), 28)
        XCTAssertEqual(calendar.component(.hour, from: next), 12)
        XCTAssertNotEqual(next.timeIntervalSince(before), 7 * 86_400)

        let back = ATHLTHStudioHomeWeek.shiftedWeek(
            from: next, offset: -1, calendar: calendar
        )
        XCTAssertEqual(back, before)
        let range = ATHLTHStudioHomeWeek.weekRange(
            containing: next, calendar: calendar
        )
        XCTAssertEqual(calendar.component(.day, from: range.start), 26)
        XCTAssertEqual(calendar.component(.day, from: range.end), 1)
        XCTAssertEqual(calendar.component(.month, from: range.end), 11)
    }

    func testWeekStartsOnMondayEvenWhenLocaleCalendarStartsOnSunday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        calendar.firstWeekday = 1
        let wednesday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 4))
        )
        let week = ATHLTHStudioHomeWeek.make(
            plans: [], standalone: [], recorded: [],
            now: wednesday, calendar: calendar
        )
        XCTAssertEqual(week.days.count, 7)
        XCTAssertEqual(calendar.component(.weekday, from: week.days[0].date), 2)
        XCTAssertEqual(calendar.component(.day, from: week.days[0].date), 2)
        XCTAssertEqual(calendar.component(.day, from: week.days[6].date), 8)
    }
    @MainActor
    func testRestDayIsVisibleButDoesNotCountAsWorkout() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "ATHLTHStudioRest.\(UUID().uuidString)")
        )
        let store = AppSessionStore(defaults: defaults)
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: .now)
        let weekday = (calendar.component(.weekday, from: now) + 5) % 7
        let monday = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -weekday, to: now)
        )
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "With rest", summary: "", weekCount: 1, startDate: monday
        ))
        var rest = session("Recovery", on: nil)
        rest.workoutCategory = "rest_day"
        store.addSession(rest, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let stored = try XCTUnwrap(store.trainingPlan(withID: plan.id))

        let week = ATHLTHStudioHomeWeek.make(
            plans: [stored], standalone: [], recorded: [], now: monday
        )
        XCTAssertEqual(week.plannedCount, 0)
        XCTAssertEqual(week.days[1].restDays.count, 1)
        XCTAssertEqual(week.days[1].restDays.first?.workout.title, "Recovery")
    }

    func testWeeklyOverviewIncludesLocalStrengthBeforeHealthSync() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let local = StrengthWorkoutLog(
            id: UUID(),
            plannedSessionID: nil,
            watchSessionID: nil,
            captureDevice: .iPhone,
            trackingMode: .simple,
            title: "Local strength",
            startedAt: today.addingTimeInterval(9 * 3_600),
            endedAt: today.addingTimeInterval(9 * 3_600 + 1_800),
            exercises: [],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil,
                duration: 1_800,
                activeCalories: nil,
                averageHeartRate: nil,
                maxHeartRate: nil
            )
        )
        let recordings = ATHLTHStudioRecordedWorkouts.merged(
            health: [], localStrength: [local]
        )
        let week = ATHLTHStudioHomeWeek.make(
            plans: [], standalone: [], recorded: recordings, now: today
        )
        XCTAssertEqual(week.recordedCount, 1)
        XCTAssertEqual(week.days.flatMap(\.recorded).first?.activity, .strength)
    }

    func testMultiplePlannedSessionsRemainSeparateOnSameDay() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let a = session("Run", on: today)
        let b = session("Strength", on: today, kind: .strength)
        let week = ATHLTHStudioHomeWeek.make(
            plans: [], standalone: [a, b], recorded: [], now: today
        )
        let day = try XCTUnwrap(week.days.first {
            calendar.isDate($0.date, inSameDayAs: today)
        })
        XCTAssertEqual(day.planned.count, 2)
        XCTAssertEqual(week.plannedCount, 2)
        XCTAssertTrue(day.restDays.isEmpty)
    }

    func testPlannedCountUsesCorrectNorwegianSingularAndPlural() {
        XCTAssertEqual(
            ATHLTHStudioHomeWeek.plannedCountLabel(0, norwegian: true),
            "0 planlagte økter"
        )
        XCTAssertEqual(
            ATHLTHStudioHomeWeek.plannedCountLabel(1, norwegian: true),
            "1 planlagt økt"
        )
        XCTAssertEqual(
            ATHLTHStudioHomeWeek.plannedCountLabel(2, norwegian: true),
            "2 planlagte økter"
        )
        XCTAssertEqual(
            ATHLTHStudioHomeWeek.plannedCountLabel(1, norwegian: false),
            "1 planned workout"
        )
        XCTAssertEqual(
            ATHLTHStudioHomeWeek.plannedCountLabel(3, norwegian: false),
            "3 planned workouts"
        )
    }

    func testSelectedDayRetainsScheduledStartTimeForHomeDetails() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 12, hour: 17, minute: 45
        )))
        let scheduled = session("Intervals", on: start)
        let week = ATHLTHStudioHomeWeek.make(
            plans: [], standalone: [scheduled], recorded: [],
            now: start, calendar: calendar
        )
        let day = try XCTUnwrap(week.days.first {
            calendar.isDate($0.date, inSameDayAs: start)
        })
        XCTAssertEqual(day.planned.count, 1)
        XCTAssertEqual(day.planned[0].workout.title, "Intervals")
        XCTAssertEqual(day.planned[0].workout.scheduledStart, start)
        XCTAssertEqual(
            calendar.dateComponents([.hour, .minute], from: day.planned[0].date),
            DateComponents(hour: 17, minute: 45)
        )
    }

    func testUntimedPlanDayNeverInventsClockTime() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "ATHLTHStudioUntimed.\(UUID().uuidString)")
        )
        let store = AppSessionStore(defaults: defaults)
        let monday = ATHLTHStudioHomeWeek.weekRange(containing: .now).start
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Untimed", summary: "", weekCount: 1,
            startDate: monday
        ))
        store.addSession(
            session("Run", on: nil),
            toDay: plan.weeks[0].days[0].id,
            inPlan: plan.id
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let week = ATHLTHStudioHomeWeek.make(
            plans: [saved], standalone: [], recorded: [], now: monday
        )
        let entry = try XCTUnwrap(week.days[0].planned.first)
        XCTAssertNil(entry.workout.scheduledStart)
    }

}
