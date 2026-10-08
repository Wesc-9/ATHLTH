import Foundation
import HealthKit
import XCTest
@testable import ATHLTH

final class TrainingPlanHealthLinkTests: XCTestCase {
    @MainActor
    private func makeStore() -> (AppSessionStore, UserDefaults, String) {
        let suite = "TrainingPlanHealthLinkTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppSessionStore(defaults: defaults), defaults, suite)
    }

    private func workout(
        activity: HKWorkoutActivityType,
        startedAt: Date
    ) -> WorkoutSummary {
        let duration: TimeInterval = 30 * 60
        return WorkoutSummary(
            workout: HKWorkout(
                activityType: activity,
                start: startedAt,
                end: startedAt.addingTimeInterval(duration),
                duration: duration,
                totalEnergyBurned: nil,
                totalDistance: nil,
                metadata: nil
            )
        )
    }

    @MainActor
    private func addRun(
        store: AppSessionStore,
        planID: UUID,
        dayID: UUID,
        time: Date
    ) -> PlannedSession {
        let run = PlannedSession(
            id: UUID(),
            title: "Easy run",
            kind: .running,
            scheduledStart: time,
            durationMinutes: 30,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil,
            runningWorkout: nil
        )
        store.addSession(run, toDay: dayID, inPlan: planID)
        return run
    }

    @MainActor
    func testSameDayHealthRunDoesNotSilentlyCompletePlan() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Calendar.current.date(from: DateComponents(
            year: 2030, month: 1, day: 8
        ))!
        guard let plan = store.createTrainingPlan(
            title: "Running", summary: "", weekCount: 1, startDate: start
        ) else { return XCTFail("Expected plan") }

        let session = addRun(
            store: store, planID: plan.id,
            dayID: plan.weeks[0].days[0].id,
            time: start
        )
        let healthRun = workout(activity: .running, startedAt: start)
        let unlinked = store.trainingPlanProgress(
            store.trainingPlan(withID: plan.id)!,
            healthWorkouts: [healthRun],
            strengthHistory: [],
            referenceDate: start.addingTimeInterval(86_400)
        )
        XCTAssertEqual(unlinked.totalSessions, 1)
        XCTAssertEqual(unlinked.completedSessions, 0)

        XCTAssertTrue(store.linkHealthWorkout(
            healthRun, toPlan: plan.id, sessionID: session.id
        ))
        let linked = store.trainingPlanProgress(
            store.trainingPlan(withID: plan.id)!,
            healthWorkouts: [healthRun],
            strengthHistory: [],
            referenceDate: start.addingTimeInterval(86_400)
        )
        XCTAssertEqual(linked.completedSessions, 1)
        XCTAssertEqual(linked.missed.count, 0)

        store.unlinkHealthWorkout(
            planID: plan.id, sessionID: session.id
        )
        let reverted = store.trainingPlanProgress(
            store.trainingPlan(withID: plan.id)!,
            healthWorkouts: [healthRun],
            strengthHistory: [],
            referenceDate: start.addingTimeInterval(86_400)
        )
        XCTAssertEqual(reverted.completedSessions, 0)
    }

    @MainActor
    func testHealthLinkMustMatchActivityAndCannotCountTwice() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Calendar.current.date(from: DateComponents(
            year: 2030, month: 1, day: 8
        ))!
        guard let plan = store.createTrainingPlan(
            title: "Two sessions", summary: "", weekCount: 1, startDate: start
        ) else { return XCTFail("Expected plan") }
        let first = addRun(
            store: store, planID: plan.id,
            dayID: plan.weeks[0].days[0].id, time: start
        )
        let second = addRun(
            store: store, planID: plan.id,
            dayID: plan.weeks[0].days[1].id, time: start
        )
        let walking = workout(activity: .walking, startedAt: start)
        let running = workout(activity: .running, startedAt: start)

        XCTAssertFalse(store.linkHealthWorkout(
            walking, toPlan: plan.id, sessionID: first.id
        ))
        XCTAssertTrue(store.linkHealthWorkout(
            running, toPlan: plan.id, sessionID: first.id
        ))
        XCTAssertFalse(store.linkHealthWorkout(
            running, toPlan: plan.id, sessionID: second.id
        ))
        let progress = store.trainingPlanProgress(
            store.trainingPlan(withID: plan.id)!,
            healthWorkouts: [walking, running],
            strengthHistory: [],
            referenceDate: start
        )
        XCTAssertEqual(progress.completedSessions, 1)
    }

    @MainActor
    func testLinkedWorkoutRemovedFromHealthIsNotCounted() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Calendar.current.date(from: DateComponents(
            year: 2030, month: 1, day: 8
        ))!
        guard let plan = store.createTrainingPlan(
            title: "Deleted workout", summary: "",
            weekCount: 1, startDate: start
        ) else { return XCTFail("Expected plan") }
        let planned = addRun(
            store: store, planID: plan.id,
            dayID: plan.weeks[0].days[0].id, time: start
        )
        let healthRun = workout(activity: .running, startedAt: start)
        XCTAssertTrue(store.linkHealthWorkout(
            healthRun, toPlan: plan.id, sessionID: planned.id
        ))
        let progress = store.trainingPlanProgress(
            store.trainingPlan(withID: plan.id)!,
            healthWorkouts: [],
            strengthHistory: [],
            referenceDate: start
        )
        XCTAssertEqual(progress.completedSessions, 0)
    }
}
