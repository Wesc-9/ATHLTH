import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHStudioDashboardHeaderPulseTests: XCTestCase {
    private func workout(
        title: String,
        on date: Date? = nil
    ) -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: title,
            kind: .running,
            scheduledStart: date,
            durationMinutes: 40,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
    }

    @MainActor
    func testWeeklyProgressCountsOnlyExplicitlyCompletedPlanWorkouts() throws {
        let suite = "ATHLTHStudioDashboardHeaderPulseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)

        let today = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Week plan", summary: "", weekCount: 1,
            startDate: today
        ))
        let planned = workout(title: "Planned intervals")
        store.addSession(planned, toDay: plan.weeks[0].days[0].id,
                         inPlan: plan.id)
        let current = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let standalone = workout(title: "Unlinked walk", on: today)
        let week = ATHLTHStudioHomeWeek.make(
            plans: [current],
            standalone: [standalone],
            recorded: [],
            now: today
        )
        XCTAssertEqual(week.plannedCount, 2)

        let pending = ATHLTHStudioDashboardHeaderPulse.make(
            week: week,
            completedOccurrenceIDs: [],
            healthAvailable: true
        )
        XCTAssertEqual(pending.plannedSessions, 1)
        XCTAssertEqual(pending.completedSessions, 0)
        XCTAssertEqual(pending.recordedMinutes, 0)

        let realPlanOccurrence = try XCTUnwrap(
            week.days.flatMap(\.planned).first {
                $0.planID == plan.id && $0.workout.id == planned.id
            }
        )
        let realCompletion = ATHLTHStudioDashboardHeaderPulse.make(
            week: week,
            completedOccurrenceIDs: [realPlanOccurrence.id],
            healthAvailable: false
        )
        XCTAssertEqual(realCompletion.completedSessions, 1)
        XCTAssertEqual(realCompletion.plannedSessions, 1)
        XCTAssertNil(realCompletion.recordedMinutes,
                     "Unavailable Health data must never appear as 0 minutes")
    }

    @MainActor
    func testCalendarNavigationDoesNotMutateTheActualWeekPulse() throws {
        let suite = "ATHLTHStudioHeaderActualWeek.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        let today = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Program", summary: "", weekCount: 2,
            startDate: today
        ))
        store.addSession(
            workout(title: "Today's program session"),
            toDay: plan.weeks[0].days[0].id,
            inPlan: plan.id
        )
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))

        let actualWeek = ATHLTHStudioHomeWeek.make(
            plans: [saved], standalone: [], recorded: [], now: today
        )
        let later = ATHLTHStudioHomeWeek.make(
            plans: [saved], standalone: [], recorded: [],
            now: ATHLTHStudioHomeWeek.shiftedWeek(
                from: today, offset: 3
            )
        )
        let todayPulse = ATHLTHStudioDashboardHeaderPulse.make(
            week: actualWeek, completedOccurrenceIDs: [],
            healthAvailable: true
        )
        let browsedPulse = ATHLTHStudioDashboardHeaderPulse.make(
            week: later, completedOccurrenceIDs: [],
            healthAvailable: true
        )
        XCTAssertEqual(todayPulse.plannedSessions, 1)
        XCTAssertEqual(browsedPulse.plannedSessions, 0)
    }
}
