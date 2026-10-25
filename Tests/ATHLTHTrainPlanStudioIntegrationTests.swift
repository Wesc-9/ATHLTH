import Foundation
import XCTest
@testable import ATHLTH

/// Checks the actual persisted Plan Studio -> scheduled workout -> completion
/// contract, not only its SwiftUI rendering.
final class ATHLTHTrainPlanStudioIntegrationTests: XCTestCase {
    @MainActor
    func testCopyingOneWorkoutToSameDayKeepsOtherSessionsAndOriginalIdentity() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Multiple sessions", summary: "", weekCount: 1,
            startDate: Calendar.current.startOfDay(for: Date())))
        let dayID = plan.weeks[0].days[0].id
        let first = workout(name: "Morning")
        let second = workout(name: "Evening")
        store.addSession(first, toDay: dayID, inPlan: plan.id)
        store.addSession(second, toDay: dayID, inPlan: plan.id)
        let version = try XCTUnwrap(store.trainingPlan(withID: plan.id)).version

        XCTAssertTrue(store.copyPlanStudioWorkout(
            planID: plan.id, sourceWorkoutID: first.id,
            targetDayID: dayID, expectedVersion: version))

        let updated = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let sessions = updated.weeks[0].days[0].sessions
        XCTAssertEqual(sessions.count, 3)
        XCTAssertTrue(sessions.contains { $0.id == first.id })
        XCTAssertTrue(sessions.contains { $0.id == second.id })
        XCTAssertEqual(sessions.filter { $0.title == first.title }.count, 2)
        XCTAssertEqual(Set(sessions.map(\.id)).count, 3)
        XCTAssertFalse(store.copyPlanStudioWorkout(
            planID: plan.id, sourceWorkoutID: first.id,
            targetDayID: dayID, expectedVersion: version))
    }

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
    func testSavingWorkoutTemplateUpdatesInPlaceAndAllowsIndependentCopy() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let original = workout(name: "Interval run")
        let id = store.saveSharedWorkout(original)
        XCTAssertEqual(store.savedWorkoutTemplates.filter { $0.id == id }.count, 1)

        var updated = original
        updated.title = "Interval run – revised"
        updated.durationMinutes = 60
        XCTAssertTrue(store.updateSavedWorkoutTemplate(updated, id: id))
        let saved = try XCTUnwrap(store.savedWorkoutTemplates.first { $0.id == id })
        XCTAssertEqual(saved.title, "Interval run – revised")
        XCTAssertEqual(saved.durationMinutes, 60)
        XCTAssertEqual(store.savedWorkoutTemplates.filter { $0.id == id }.count, 1)

        let newID = store.saveSharedWorkout(updated)
        XCTAssertNotEqual(newID, id)
        XCTAssertEqual(store.savedWorkoutTemplates.count, 2)
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
    @MainActor
    func testCopyingFromPlanStudioCreatesIndependentSetIDs() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Copy safety", summary: "",
            weekCount: 2,
            startDate: Calendar.current.startOfDay(for: Date())
        ))
        let sourceDay = plan.weeks[0].days[0]
        let targetDay = plan.weeks[1].days[0]
        var source = workout()
        var curl = PlannedExercise(
            id: UUID(), exerciseID: nil,
            embeddedExercise: ExerciseSnapshot(
                name: "Bicepscurl", instructions: [],
                primaryMuscles: ["biceps"],
                secondaryMuscles: [], equipment: ["Manualer"],
                imageURL: nil
            ), sets: 2, reps: 10,
            targetWeightKilograms: 12, targetRPE: nil,
            restSeconds: 60, notes: nil
        )
        curl.setTargets = [
            PlannedExerciseSetTarget(reps: 10, weightKilograms: 12),
            PlannedExerciseSetTarget(reps: 8, weightKilograms: 14)
        ]
        source.exercises = [curl]
        store.addSession(source, toDay: sourceDay.id, inPlan: plan.id)
        let version = try XCTUnwrap(store.trainingPlan(withID: plan.id)).version
        XCTAssertTrue(store.copyPlanStudioWorkout(
            planID: plan.id, sourceWorkoutID: source.id,
            targetDayID: targetDay.id, expectedVersion: version
        ))

        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let original = try XCTUnwrap(saved.weeks[0].days[0].sessions.first)
        let copied = try XCTUnwrap(saved.weeks[1].days[0].sessions.first)
        XCTAssertNotEqual(original.id, copied.id)
        XCTAssertNotEqual(original.exercises[0].id, copied.exercises[0].id)
        XCTAssertEqual(original.exercises[0].setTargets?.map(\.weightKilograms),
                       copied.exercises[0].setTargets?.map(\.weightKilograms))
        XCTAssertNotEqual(original.exercises[0].setTargets?.map(\.id),
                          copied.exercises[0].setTargets?.map(\.id))
        XCTAssertFalse(store.copyPlanStudioWorkout(
            planID: plan.id, sourceWorkoutID: source.id,
            targetDayID: targetDay.id, expectedVersion: version
        ))
    }

    @MainActor
    func testMovingPlannedWorkoutCannotMoveCompletedOrStaleSession() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let today = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Safe move", summary: "",
            weekCount: 1, startDate: today
        ))
        let sourceDay = plan.weeks[0].days[0]
        let original = workout()
        store.addSession(original, toDay: sourceDay.id, inPlan: plan.id)
        let version = try XCTUnwrap(store.trainingPlan(withID: plan.id)).version
        let tomorrow = try XCTUnwrap(Calendar.current.date(
            byAdding: .day, value: 1, to: today
        ))

        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: original.id, completed: true
        )
        XCTAssertFalse(store.movePlanStudioWorkout(
            planID: plan.id, workoutID: original.id, targetDate: tomorrow,
            expectedVersion: version, healthWorkouts: [], strengthHistory: []
        ))
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: original.id, completed: false
        )
        XCTAssertTrue(store.movePlanStudioWorkout(
            planID: plan.id, workoutID: original.id, targetDate: tomorrow,
            expectedVersion: version, healthWorkouts: [], strengthHistory: []
        ))
        XCTAssertFalse(store.movePlanStudioWorkout(
            planID: plan.id, workoutID: original.id, targetDate: today,
            expectedVersion: version, healthWorkouts: [], strengthHistory: []
        ))

        let moved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertTrue(moved.weeks[0].days[0].sessions.isEmpty)
        XCTAssertEqual(moved.weeks[0].days[1].sessions.map(\.id), [original.id])
    }

    @MainActor
    func testMovingAcrossWeekBoundaryPreservesIdentityAndStartTime() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Cross-week move", summary: "",
            weekCount: 2, startDate: today
        ))
        let originalStart = try XCTUnwrap(calendar.date(
            bySettingHour: 7, minute: 35, second: 0, of: today
        ))
        let original = PlannedSession(
            id: UUID(), title: "Morning run", kind: .running,
            scheduledStart: originalStart, durationMinutes: 35,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        store.addSession(original, toDay: plan.weeks[0].days[0].id,
                         inPlan: plan.id)
        let before = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let target = try XCTUnwrap(calendar.date(
            byAdding: .day, value: 8, to: today
        ))
        XCTAssertTrue(store.movePlanStudioWorkout(
            planID: plan.id, workoutID: original.id, targetDate: target,
            expectedVersion: before.version,
            healthWorkouts: [], strengthHistory: []
        ))
        let after = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(after.version, before.version + 1)
        XCTAssertTrue(after.weeks[0].days[0].sessions.isEmpty)
        let moved = try XCTUnwrap(after.weeks[1].days[1].sessions.first)
        XCTAssertEqual(moved.id, original.id)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(moved.scheduledStart)), 7)
        XCTAssertEqual(calendar.component(.minute, from: try XCTUnwrap(moved.scheduledStart)), 35)
        XCTAssertFalse(store.isPlanSessionCompleted(
            planID: plan.id, sessionID: moved.id,
            healthWorkouts: [], strengthHistory: []
        ))
    }

    @MainActor
    func testMovingWorkoutRejectsDatesOutsidePlanWithoutMutation() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Move boundaries", summary: "",
            weekCount: 1, startDate: today
        ))
        let original = workout()
        store.addSession(original, toDay: plan.weeks[0].days[0].id,
                         inPlan: plan.id)
        let before = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let beyond = try XCTUnwrap(calendar.date(
            byAdding: .day, value: 7, to: today
        ))
        XCTAssertFalse(store.movePlanStudioWorkout(
            planID: plan.id, workoutID: original.id, targetDate: beyond,
            expectedVersion: before.version,
            healthWorkouts: [], strengthHistory: []
        ))
        let after = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(after.version, before.version)
        XCTAssertEqual(after.weeks[0].days[0].sessions.map(\.id), [original.id])
    }

    @MainActor
    func testRemovePlanStudioWorkoutProtectsCompletedAndStaleEditors() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Safe removal", summary: "",
            weekCount: 1,
            startDate: Calendar.current.startOfDay(for: Date())
        ))
        let dayID = plan.weeks[0].days[0].id
        let original = workout()
        store.addSession(original, toDay: dayID, inPlan: plan.id)
        let version = try XCTUnwrap(store.trainingPlan(withID: plan.id)).version

        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: original.id, completed: true
        )
        XCTAssertFalse(store.removePlanStudioWorkout(
            planID: plan.id, workoutID: original.id,
            dayID: dayID, expectedVersion: version,
            healthWorkouts: [], strengthHistory: []
        ))
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: original.id, completed: false
        )
        store.addSession(workout(name: "New session"), toDay: dayID, inPlan: plan.id)
        XCTAssertFalse(store.removePlanStudioWorkout(
            planID: plan.id, workoutID: original.id,
            dayID: dayID, expectedVersion: version,
            healthWorkouts: [], strengthHistory: []
        ))
        let latest = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertTrue(store.removePlanStudioWorkout(
            planID: plan.id, workoutID: original.id, dayID: dayID,
            expectedVersion: latest.version,
            healthWorkouts: [], strengthHistory: []
        ))
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(saved.weeks[0].days[0].sessions.count, 1)
    }

    @MainActor
    func testPastUnfinishedWorkoutCanBeRemovedWithoutTouchingCompletedOrSkipped() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let yesterday = try XCTUnwrap(Calendar.current.date(
            byAdding: .day, value: -1,
            to: Calendar.current.startOfDay(for: Date())
        ))
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Yesterday's plan", summary: "",
            weekCount: 1, startDate: yesterday
        ))
        let dayID = plan.weeks[0].days[0].id
        let unfinished = workout(name: "Unfinished workout")
        let completed = workout(name: "Completed workout")
        let skipped = workout(name: "Skipped workout")
        for item in [unfinished, completed, skipped] {
            store.addSession(item, toDay: dayID, inPlan: plan.id)
        }
        let before = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: completed.id, completed: true
        )
        store.setPlanSessionSkipped(
            planID: plan.id, sessionID: skipped.id, skipped: true
        )

        XCTAssertTrue(store.removePlanStudioWorkout(
            planID: plan.id, workoutID: unfinished.id, dayID: dayID,
            expectedVersion: before.version,
            healthWorkouts: [], strengthHistory: []
        ))
        let after = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(after.version, before.version + 1)
        XCTAssertEqual(
            Set(after.weeks[0].days[0].sessions.map(\.id)),
            Set([completed.id, skipped.id])
        )
        XCTAssertFalse(store.removePlanStudioWorkout(
            planID: plan.id, workoutID: completed.id, dayID: dayID,
            expectedVersion: after.version,
            healthWorkouts: [], strengthHistory: []
        ))
        XCTAssertFalse(store.removePlanStudioWorkout(
            planID: plan.id, workoutID: skipped.id, dayID: dayID,
            expectedVersion: after.version,
            healthWorkouts: [], strengthHistory: []
        ))
    }

    @MainActor
    func testMovingToSameDayDoesNotChangePlanOrVersion() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Calendar.current.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "No-op move", summary: "",
            weekCount: 1, startDate: start
        ))
        let original = workout(name: "Keep on same day")
        store.addSession(original, toDay: plan.weeks[0].days[0].id,
                         inPlan: plan.id)
        let before = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let sameDayLater = try XCTUnwrap(Calendar.current.date(
            byAdding: .hour, value: 12, to: start
        ))

        XCTAssertFalse(store.movePlanStudioWorkout(
            planID: plan.id, workoutID: original.id,
            targetDate: sameDayLater,
            expectedVersion: before.version,
            healthWorkouts: [], strengthHistory: []
        ))
        let after = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(after.version, before.version)
        XCTAssertEqual(after.weeks[0].days[0].sessions.map(\.id),
                       [original.id])
    }

    @MainActor
    func testPlanStudioSaveNormalizesScheduledDayAndPreservesClock() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Scheduled time integrity", summary: "",
            weekCount: 2, startDate: today
        ))
        let dayID = plan.weeks[0].days[2].id
        var draft = workout(name: "Timed run")
        let foreignDate = try XCTUnwrap(calendar.date(
            byAdding: .day, value: 9, to: today
        ))
        draft.scheduledStart = try XCTUnwrap(calendar.date(
            bySettingHour: 7, minute: 35, second: 0, of: foreignDate
        ))
        let before = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertTrue(store.savePlanStudioWorkout(
            draft, inPlan: plan.id, dayID: dayID,
            editingWorkoutID: nil, expectedPlanVersion: before.version,
            healthWorkouts: [], strengthHistory: []
        ))
        let saved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let scheduled = try XCTUnwrap(saved.weeks[0].days[2]
            .sessions.first?.scheduledStart)
        let expectedDay = try XCTUnwrap(calendar.date(
            byAdding: .day, value: 2, to: today
        ))
        XCTAssertTrue(calendar.isDate(scheduled, inSameDayAs: expectedDay))
        XCTAssertEqual(calendar.component(.hour, from: scheduled), 7)
        XCTAssertEqual(calendar.component(.minute, from: scheduled), 35)
        XCTAssertEqual(saved.weeks[0].days[2].sessions.first?.id, draft.id)
    }

    @MainActor
    func testPlanStudioEditKeepsWorkoutIdentityAndNormalizesTime() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Edit scheduled session", summary: "",
            weekCount: 2, startDate: today
        ))
        let dayID = plan.weeks[0].days[1].id
        let original = workout(name: "Original workout")
        store.addSession(original, toDay: dayID, inPlan: plan.id)
        let before = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        var changed = original
        changed.title = "Updated workout"
        let differentDay = try XCTUnwrap(calendar.date(
            byAdding: .day, value: 8, to: today
        ))
        changed.scheduledStart = try XCTUnwrap(calendar.date(
            bySettingHour: 19, minute: 15, second: 0, of: differentDay
        ))
        XCTAssertTrue(store.savePlanStudioWorkout(
            changed, inPlan: plan.id, dayID: dayID,
            editingWorkoutID: original.id, expectedPlanVersion: before.version,
            healthWorkouts: [], strengthHistory: []
        ))
        let after = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let edited = try XCTUnwrap(after.weeks[0].days[1].sessions.first)
        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.title, "Updated workout")
        XCTAssertEqual(after.weeks[0].days[1].sessions.count, 1)
        let scheduled = try XCTUnwrap(edited.scheduledStart)
        let expected = try XCTUnwrap(calendar.date(
            byAdding: .day, value: 1, to: today
        ))
        XCTAssertTrue(calendar.isDate(scheduled, inSameDayAs: expected))
        XCTAssertEqual(calendar.component(.hour, from: scheduled), 19)
        XCTAssertEqual(calendar.component(.minute, from: scheduled), 15)
    }

    @MainActor
    func testMovingPlannedWorkoutPreservesIdentityAndRejectsStaleVersion() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Move safety", summary: "", weekCount: 2, startDate: today
        ))
        let original = workout(name: "Planned strength")
        store.addSession(original, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let before = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        let destination = try XCTUnwrap(calendar.date(byAdding: .day, value: 8, to: today))

        XCTAssertTrue(store.movePlanStudioWorkout(
            planID: plan.id, workoutID: original.id, targetDate: destination,
            expectedVersion: before.version,
            healthWorkouts: [], strengthHistory: []
        ))
        let moved = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(moved.version, before.version + 1)
        XCTAssertFalse(moved.weeks[0].days[0].sessions.contains { $0.id == original.id })
        XCTAssertEqual(moved.weeks[1].days[1].sessions.first?.id, original.id)
        XCTAssertFalse(store.movePlanStudioWorkout(
            planID: plan.id, workoutID: original.id, targetDate: today,
            expectedVersion: before.version,
            healthWorkouts: [], strengthHistory: []
        ))
    }

    @MainActor
    func testCompletedWorkoutCannotBeMovedFromPlanStudio() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Completed move guard", summary: "", weekCount: 1, startDate: today
        ))
        let original = workout()
        store.addSession(original, toDay: plan.weeks[0].days[0].id, inPlan: plan.id)
        let before = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: original.id, completed: true
        )
        let destination = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        XCTAssertFalse(store.movePlanStudioWorkout(
            planID: plan.id, workoutID: original.id, targetDate: destination,
            expectedVersion: before.version,
            healthWorkouts: [], strengthHistory: []
        ))
        let after = try XCTUnwrap(store.trainingPlan(withID: plan.id))
        XCTAssertEqual(after.weeks[0].days[0].sessions.first?.id, original.id)
    }

    func testStructuredCompletionKeepsPlanIdentityAndDecodesLegacyHistory() throws {
        let planID = UUID()
        let sessionID = UUID()
        let completion = StructuredWorkoutCompletion(
            id: UUID(),
            workoutTemplateID: nil,
            sourceWorkoutID: sessionID,
            title: "Intervals",
            category: "Running",
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_600),
            completedBlockCount: 3,
            totalBlockCount: 4,
            sourcePlanID: planID
        )
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(completion)
        let restored = try JSONDecoder().decode(
            StructuredWorkoutCompletion.self, from: encoded
        )
        XCTAssertEqual(restored.sourcePlanID, planID)
        XCTAssertEqual(restored.sourceWorkoutID, sessionID)
        XCTAssertEqual(restored.completedBlockCount, 3)

        // Older stored records have no sourcePlanID. Keep them readable.
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacy.removeValue(forKey: "sourcePlanID")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let decodedLegacy = try JSONDecoder().decode(
            StructuredWorkoutCompletion.self, from: legacyData
        )
        XCTAssertNil(decodedLegacy.sourcePlanID)
        XCTAssertEqual(decodedLegacy.sourceWorkoutID, sessionID)
    }

    @MainActor
    func testCompletionIsScopedToExactPlanEvenWhenWorkoutIDsMatch() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let today = Calendar.current.startOfDay(for: Date())
        let first = try XCTUnwrap(store.createTrainingPlan(
            title: "First program", summary: "", weekCount: 1, startDate: today
        ))
        // Overlapping plans are intentionally rejected. The same workout
        // identifier must still be isolated by plan even across sequential
        // plans with non-overlapping date windows.
        XCTAssertNil(store.createTrainingPlan(
            title: "Overlapping program", summary: "", weekCount: 1,
            startDate: today
        ))
        let nextWeek = try XCTUnwrap(Calendar.current.date(
            byAdding: .day, value: 7, to: today
        ))
        let second = try XCTUnwrap(store.createTrainingPlan(
            title: "Second program", summary: "", weekCount: 1,
            startDate: nextWeek
        ))
        let shared = workout(name: "Same workout identifier")
        store.addSession(shared, toDay: first.weeks[0].days[0].id, inPlan: first.id)
        store.addSession(shared, toDay: second.weeks[0].days[0].id, inPlan: second.id)

        store.setPlanSessionManuallyCompleted(
            planID: first.id, sessionID: shared.id, completed: true
        )
        XCTAssertTrue(store.isPlanSessionCompleted(
            planID: first.id, sessionID: shared.id,
            healthWorkouts: [], strengthHistory: []
        ))
        XCTAssertFalse(store.isPlanSessionCompleted(
            planID: second.id, sessionID: shared.id,
            healthWorkouts: [], strengthHistory: []
        ))

        store.setPlanSessionSkipped(
            planID: first.id, sessionID: shared.id, skipped: true
        )
        XCTAssertFalse(store.isPlanSessionCompleted(
            planID: first.id, sessionID: shared.id,
            healthWorkouts: [], strengthHistory: []
        ))
    }

    @MainActor
    func testRemovedWorkoutCannotBeCreditedByStaleManualCompletion() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let plan = try XCTUnwrap(store.createTrainingPlan(
            title: "Removed session", summary: "", weekCount: 1,
            startDate: Calendar.current.startOfDay(for: Date())
        ))
        let missingID = UUID()
        store.setPlanSessionManuallyCompleted(
            planID: plan.id, sessionID: missingID, completed: true
        )
        XCTAssertFalse(store.isPlanSessionCompleted(
            planID: plan.id, sessionID: missingID,
            healthWorkouts: [], strengthHistory: []
        ))
    }

}
