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
}
