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
    func testBreakdownSeparatesRunningStrengthAndManualEvidence() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Category breakdown", summary: "",
            weekCount: 1, startDate: start
        ))
        let run = plannedRun(title: "Run")
        var lift = plannedRun(title: "Strength")
        lift.kind = .strength
        var walk = plannedRun(title: "Walk")
        walk.kind = .walking
        store.addSession(run, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.addSession(lift, toDay: plan.weeks[0].days[1].id, inPlan: plan.id)
        store.addSession(walk, toDay: plan.weeks[0].days[2].id, inPlan: plan.id)
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: lift.id, completed: true
        )
        store.setPlanSessionSkipped(
            planID: plan.id, sessionID: walk.id, skipped: true
        )
        let healthWorkout = healthRun(on: start)
        XCTAssertTrue(store.linkHealthWorkout(
            healthWorkout, toPlan: plan.id, sessionID: run.id
        ))
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let report = ATHLTHPlanActualProgress.inspect(
            plan: saved, store: store, healthWorkouts: [healthWorkout],
            strengthHistory: []
        )
        let week = try XCTUnwrap(report.weeks.first)
        XCTAssertEqual(week.running.planned, 1)
        XCTAssertEqual(week.running.recorded, 1)
        XCTAssertEqual(week.running.manuallyMarked, 0)
        XCTAssertEqual(week.strength.planned, 1)
        XCTAssertEqual(week.strength.recorded, 0)
        XCTAssertEqual(week.strength.manuallyMarked, 1)
        XCTAssertEqual(week.other.planned, 1)
        XCTAssertEqual(week.other.skipped, 1)
        XCTAssertEqual(report.totalCompleted, 2)
        XCTAssertEqual(report.totalPlanned, 3)
        XCTAssertEqual(report.totalRecorded, 1)
        XCTAssertEqual(report.totalManuallyMarked, 1)
        XCTAssertEqual(report.running.completed, 1)
        XCTAssertEqual(report.strength.completed, 1)
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

    @MainActor
    func testExplicitRestDayDoesNotCountAsAWorkoutOrCompletion() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Recovery week",
            summary: "",
            weekCount: 1,
            startDate: Calendar.current.startOfDay(for: Date())
        ))
        let rest = PlannedSession(
            id: UUID(),
            title: "Hviledag",
            kind: .recovery,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil,
            workoutCategory: "rest_day"
        )

        XCTAssertTrue(rest.isExplicitRestDay)
        store.addSession(rest, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: rest.id, completed: true
        )
        let report = ATHLTHPlanActualProgress.inspect(
            plan: try XCTUnwrap(store.trainingPlan(withID: plan.id)),
            store: store, healthWorkouts: [], strengthHistory: []
        )
        XCTAssertEqual(report.totalPlanned, 0)
        XCTAssertEqual(report.totalCompleted, 0)
        XCTAssertFalse(store.isPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: rest.id
        ))

        let run = plannedRun(title: "Cannot override a rest day")
        store.addSession(run, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let day = try XCTUnwrap(store.trainingPlan(withID: plan.id)?.weeks[0].days[0])
        XCTAssertEqual(day.sessions.map(\.id), [rest.id])
    }
}
