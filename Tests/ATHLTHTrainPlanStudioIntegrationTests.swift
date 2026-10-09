import Foundation
import XCTest
@testable import ATHLTH

/// Checks the actual persisted Plan Studio -> scheduled workout -> completion
/// contract, not only its SwiftUI rendering.
final class ATHLTHTrainPlanStudioIntegrationTests: XCTestCase {
    @MainActor
    private func makeStore() -> (AppSessionStore, UserDefaults, String) {
        let name = "ATHLTHTrainPlanStudioIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (AppSessionStore(defaults: defaults), defaults, name)
    }

    private func workout(
        id: UUID = UUID(),
        name: String = "Upper body"
    ) -> PlannedSession {
        PlannedSession(
            id: id, title: name, kind: .strength,
            scheduledStart: nil, durationMinutes: 45,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
    }

    @MainActor
    func testNewWorkoutPersistsInChosenDayAndChangesPlanVersion() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let today = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Plan Studio", summary: "",
            weekCount: 3, startDate: today
        ))
        let targetDayID = plan.weeks[1].days[2].id
        let prepared = workout()
        XCTAssertTrue(store.savePlanStudioWorkout(
            prepared, inPlan: plan.id,
            dayID: targetDayID,
            editingWorkoutID: nil,
            expectedPlanVersion: plan.version,
            healthWorkouts: [], strengthHistory: []
        ))

        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(saved.version, plan.version + 1)
        XCTAssertEqual(saved.weeks[1].days[2].sessions.map(\.id), [prepared.id])
        XCTAssertTrue(saved.weeks[0].days[0].sessions.isEmpty)
        XCTAssertFalse(store.isPlanSessionCompleted(
            planID: plan.id, sessionID: prepared.id,
            healthWorkouts: [], strengthHistory: []
        ))
    }

    @MainActor
    func testStaleEditorCannotReplaceMoreRecentPlanChanges() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let today = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Stale editor", summary: "",
            weekCount: 1, startDate: today
        ))
        let day = plan.weeks[0].days[0]
        let first = workout(name: "Existing session")
        store.addSession(first, toDay: day.id, inPlan: plan.id)
        let initialVersion = try XCTUnwrap(
            store.trainingPlan(withID: plan.id)
        ).version
        store.addSession(workout(name: "Newer update"),
                         toDay: day.id, inPlan: plan.id)

        let changed = workout(id: first.id, name: "Stale overwrite")
        XCTAssertFalse(store.savePlanStudioWorkout(
            changed, inPlan: plan.id,
            dayID: day.id, editingWorkoutID: first.id,
            expectedPlanVersion: initialVersion,
            healthWorkouts: [], strengthHistory: []
        ))
        let current = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(current.weeks[0].days[0].sessions[0].title,
                       "Existing session")
        XCTAssertEqual(current.weeks[0].days[0].sessions.count, 2)
    }

    @MainActor
    func testCompletedAndSkippedWorkoutsCannotBeEdited() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "History safety", summary: "",
            weekCount: 1,
            startDate: Calendar.current.startOfDay(for: Date())
        ))
        let day = plan.weeks[0].days[0]
        let original = workout()
        store.addSession(original, toDay: day.id, inPlan: plan.id)
        let version = try XCTUnwrap(
            store.trainingPlan(withID: plan.id)
        ).version
        let proposed = workout(id: original.id, name: "Should not overwrite")

        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: original.id, completed: true
        )
        XCTAssertFalse(store.savePlanStudioWorkout(
            proposed, inPlan: plan.id, dayID: day.id,
            editingWorkoutID: original.id, expectedPlanVersion: version,
            healthWorkouts: [], strengthHistory: []
        ))
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: original.id, completed: false
        )
        store.setPlanSessionSkipped(
            planID: plan.id, sessionID: original.id, skipped: true
        )
        XCTAssertFalse(store.savePlanStudioWorkout(
            proposed, inPlan: plan.id, dayID: day.id,
            editingWorkoutID: original.id, expectedPlanVersion: version,
            healthWorkouts: [], strengthHistory: []
        ))
        let current = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(current.weeks[0].days[0].sessions[0].title,
                       original.title)
    }

    @MainActor
    func testPastWorkoutAndDuplicateIDCannotBeInserted() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let past = Calendar.current.date(
            byAdding: .day, value: -10, to: Date()
        )!
        let pastPlan = try XCTUnwrap(store.createTrainingPlan(
            title: "Historical plan", summary: "",
            weekCount: 1, startDate: past
        ))
        XCTAssertFalse(store.savePlanStudioWorkout(
            workout(), inPlan: pastPlan.id,
            dayID: pastPlan.weeks[0].days[0].id,
            editingWorkoutID: nil,
            expectedPlanVersion: pastPlan.version,
            healthWorkouts: [], strengthHistory: []
        ))

        let fresh = try XCTUnwrap(store.createTrainingPlan(
            title: "New plan", summary: "",
            weekCount: 1, startDate: Calendar.current.startOfDay(for: Date())
        ))
        let workout = workout()
        store.addSession(workout, toDay: fresh.weeks[0].days[0].id,
                         inPlan: fresh.id)
        let version = try XCTUnwrap(
            store.trainingPlan(withID: fresh.id)
        ).version
        XCTAssertFalse(store.savePlanStudioWorkout(
            workout, inPlan: fresh.id,
            dayID: fresh.weeks[0].days[0].id,
            editingWorkoutID: nil,
            expectedPlanVersion: version,
            healthWorkouts: [], strengthHistory: []
        ))
        XCTAssertEqual(
            store.trainingPlan(withID: fresh.id)?
                .weeks[0].days[0].sessions.count, 1
        )
    }

    @MainActor
    func testPlannedAndCompletedCountsRemainSeparate() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Real progress", summary: "",
            weekCount: 1, startDate: Calendar.current.startOfDay(for: Date())
        ))
        let day = plan.weeks[0].days[0]
        let first = workout()
        let second = workout(name: "Another session")
        store.addSession(first, toDay: day.id, inPlan: plan.id)
        store.addSession(second, toDay: day.id, inPlan: plan.id)
        var current = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let initially = store.trainingPlanProgress(
            current,
            healthWorkouts: [], strengthHistory: [],
            referenceDate: Date()
        )
        XCTAssertEqual(initially.totalSessions, 2)
        XCTAssertEqual(initially.completedSessions, 0)

        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: first.id, completed: true
        )
        current = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let finished = store.trainingPlanProgress(
            current,
            healthWorkouts: [], strengthHistory: [],
            referenceDate: Date()
        )
        XCTAssertEqual(finished.totalSessions, 2)
        XCTAssertEqual(finished.completedSessions, 1)
    }
}
