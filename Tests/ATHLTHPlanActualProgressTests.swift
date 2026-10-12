import Foundation
import HealthKit
import XCTest
@testable import ATHLTH

final class ATHLTHPlanActualProgressTests: XCTestCase {
    @MainActor
    private func makeStore() -> (AppSessionStore, UserDefaults, String) {
        let suite = "ATHLTHPlanActualProgressTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppSessionStore(defaults: defaults), defaults, suite)
    }

    private func plannedRun(title: String) -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: title,
            kind: .running,
            scheduledStart: nil,
            durationMinutes: 30,
            targetDistanceKilometers: 5,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
    }

    private func healthRun(on start: Date) -> WorkoutSummary {
        let duration: TimeInterval = 30 * 60
        return WorkoutSummary(workout: HKWorkout(
            activityType: .running,
            start: start,
            end: start.addingTimeInterval(duration),
            duration: duration,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: nil
        ))
    }

    @MainActor
    func testCompletionOverlayCountsOnlyExplicitlyLinkedOrManuallyMarked() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Progress overlay",
            summary: "",
            weekCount: 2,
            startDate: start
        ))
        let first = plannedRun(title: "Monday run")
        let second = plannedRun(title: "Tuesday run")
        let third = plannedRun(title: "Week two run")

        store.addSession(first, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(second, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        store.addSession(third, toDay: plan.weeks[1].days[0].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let workout = healthRun(on: start)

        func observed() -> ATHLTHPlanActualProgress.Report {
            ATHLTHPlanActualProgress.inspect(
                plan: saved,
                store: store,
                healthWorkouts: [workout],
                strengthHistory: []
            )
        }

        let initial = observed()
        XCTAssertEqual(initial.totalPlanned, 3)
        XCTAssertEqual(initial.totalCompleted, 0)
        XCTAssertEqual(initial.weeks.map(\.completed), [0, 0])

        XCTAssertTrue(store.linkHealthWorkout(
            workout, toPlan: plan.id, sessionID: first.id
        ))
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: second.id, completed: true
        )
        var report = observed()
        XCTAssertEqual(report.totalCompleted, 2)
        XCTAssertEqual(report.totalRecorded, 1)
        XCTAssertEqual(report.totalManuallyMarked, 1)
        XCTAssertEqual(report.weeks.map(\.completed), [2, 0])
        XCTAssertEqual(report.weeks[0].completedRunning, 2)
        XCTAssertEqual(report.weeks[1].remaining, 1)

        // Both a Health link and manual completion still count as one session.
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: first.id, completed: true
        )
        report = observed()
        XCTAssertEqual(report.totalCompleted, 2)
        XCTAssertEqual(report.totalRecorded, 0)
        XCTAssertEqual(report.totalManuallyMarked, 2)

        store.setPlanSessionSkipped(
            planID: plan.id, sessionID: second.id, skipped: true
        )
        report = observed()
        XCTAssertEqual(report.totalCompleted, 1)
        XCTAssertEqual(report.totalSkipped, 1)
        XCTAssertEqual(report.weeks[0].remaining, 0)
    }

    @MainActor
    func testUnlinkedHealthAndFuturePlannedWorkoutsRemainIncomplete() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let future = Calendar.current.date(byAdding: .day, value: 20, to: Date())!
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Future plan", summary: "",
            weekCount: 1, startDate: future
        ))
        let workout = plannedRun(title: "Unlinked")
        store.addSession(workout, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let result = ATHLTHPlanActualProgress.inspect(
            plan: saved, store: store,
            healthWorkouts: [healthRun(on: future)],
            strengthHistory: []
        )
        XCTAssertEqual(result.totalPlanned, 1)
        XCTAssertEqual(result.totalCompleted, 0)
        XCTAssertEqual(result.totalSkipped, 0)
        XCTAssertEqual(result.weeks.first?.remaining, 1)
    }
}
