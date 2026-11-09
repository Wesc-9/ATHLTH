import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHStudioScheduleTests: XCTestCase {
    @MainActor
    func testUpcomingIncludesPlanAndIndependentSessionsWithoutDuplicates() throws {
        let suite = "ATHLTHStudioScheduleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Studio", summary: "", weekCount: 2, startDate: today
        ))
        let planWorkout = PlannedSession(
            id: UUID(), title: "Tempo run", kind: .running, scheduledStart: nil,
            durationMinutes: 40, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil, exercises: [], notes: nil
        )
        store.addSession(planWorkout, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        let storedPlan = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let independent = PlannedSession(
            id: UUID(), title: "Walk", kind: .walking, scheduledStart: tomorrow,
            durationMinutes: 30, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil, exercises: [], notes: nil
        )
        let result = ATHLTHStudioSchedule.upcoming(
            plans: [storedPlan, storedPlan],
            standalone: [independent, independent],
            now: today,
            days: 7
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.id)).count, 2)
        XCTAssertTrue(result.contains { $0.workout.id == planWorkout.id && $0.planTitle == "Studio" })
        XCTAssertTrue(result.contains { $0.workout.id == independent.id && $0.planTitle == nil })
    }

    @MainActor
    func testPausedAndDeactivatedPlansAreExcluded() throws {
        let suite = "ATHLTHStudioScheduleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        let today = Calendar.current.startOfDay(for: .now)
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Paused", summary: "", weekCount: 1, startDate: today
        ))
        let workout = PlannedSession(
            id: UUID(), title: "Easy run", kind: .running, scheduledStart: nil,
            durationMinutes: 25, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil, exercises: [], notes: nil
        )
        store.addSession(workout, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let stored = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(ATHLTHStudioSchedule.upcoming(plans: [stored], standalone: [], now: today).count, 1)
        XCTAssertTrue(ATHLTHStudioSchedule.upcoming(
            plans: [stored], standalone: [], pausedPlanIDs: [plan.id], now: today
        ).isEmpty)
        XCTAssertTrue(ATHLTHStudioSchedule.upcoming(
            plans: [stored], standalone: [], deactivatedPlanIDs: [plan.id], now: today
        ).isEmpty)
    }

    func testUndatedStandaloneSessionsAndRestDaysNeverAppear() {
        let undated = PlannedSession(
            id: UUID(), title: "Undated", kind: .running, scheduledStart: nil,
            durationMinutes: 20, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil, exercises: [], notes: nil
        )
        var rest = undated
        rest.workoutCategory = "rest_day"
        rest.scheduledStart = .now
        let rows = ATHLTHStudioSchedule.upcoming(plans: [], standalone: [undated, rest])
        XCTAssertTrue(rows.isEmpty)
    }
    func testNextWorkoutIgnoresPastExplicitStartButKeepsUntimedToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 9, hour: 12, minute: 30
        )))
        let past = try XCTUnwrap(calendar.date(byAdding: .hour, value: -4, to: today))
        let later = try XCTUnwrap(calendar.date(byAdding: .hour, value: 2, to: today))

        func make(_ date: Date?) -> PlannedSession {
            PlannedSession(
                id: UUID(), title: "Run", kind: .running,
                scheduledStart: date, durationMinutes: 40,
                targetDistanceKilometers: nil,
                targetPaceSecondsPerKilometer: nil, routeID: nil,
                exercises: [], notes: nil
            )
        }

        let expired = make(past)
        let future = make(later)
        let untimed = make(nil)
        XCTAssertFalse(ATHLTHStudioSchedule.isUpcoming(.init(
            id: "past", workout: expired, date: past,
            planTitle: nil, planID: nil
        ), now: today, calendar: calendar))
        XCTAssertTrue(ATHLTHStudioSchedule.isUpcoming(.init(
            id: "future", workout: future, date: later,
            planTitle: nil, planID: nil
        ), now: today, calendar: calendar))
        XCTAssertTrue(ATHLTHStudioSchedule.isUpcoming(.init(
            id: "untimed", workout: untimed,
            date: calendar.startOfDay(for: today),
            planTitle: nil, planID: nil
        ), now: today, calendar: calendar))
    }

}
