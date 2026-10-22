import Foundation
import XCTest
@testable import ATHLTH

final class HybridStrengthRunningSessionTests: XCTestCase {
    private func emptyStrengthPlan() -> PlannedSession {
        PlannedSession(
            id: UUID(), title: "Strength", kind: .strength,
            scheduledStart: nil, durationMinutes: 30,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
    }

    private func intervalPlan() -> PlannedSession {
        let template = RunningWorkoutLibraryStore.builtInTemplates.first {
            $0.title == "4 × 4 intervaller"
        }!
        return PlannedSession(
            id: UUID(), title: template.title, kind: .running,
            scheduledStart: nil, durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: template.summary,
            runningWorkout: template
        )
    }

    @MainActor
    func testFourByFourAppendsNinePhasesUnderOneWorkoutID() throws {
        let store = StrengthWorkoutStore()
        let watchSessionID = UUID()
        store.start(
            session: emptyStrengthPlan(), watchSessionID: watchSessionID,
            trackingMode: .advanced, captureDevice: .appleWatch
        )
        let before = try XCTUnwrap(store.activeWorkout?.id)
        XCTAssertTrue(store.appendWorkoutDuringSession(intervalPlan()))

        let workout = try XCTUnwrap(store.activeWorkout)
        XCTAssertEqual(workout.id, before)
        XCTAssertEqual(workout.watchSessionID, watchSessionID)
        XCTAssertEqual(workout.captureDevice, .appleWatch)
        XCTAssertEqual(workout.exercises.count, 1)

        let phases = try XCTUnwrap(workout.exercises.first)
        XCTAssertTrue(phases.isEmbeddedRunningInterval == true)
        XCTAssertEqual(phases.sets.count, 9)
        XCTAssertEqual(
            phases.sets.compactMap(\.plannedDurationSeconds).reduce(0, +),
            42 * 60
        )
        XCTAssertTrue(phases.sets.allSatisfy { $0.hybridPhaseKind != nil })
        XCTAssertEqual(workout.totalCompletedSets, 0)
    }

    @MainActor
    func testExistingStrengthSetIDsSurviveAppendingAnotherWorkout() throws {
        let exercise = PlannedExercise(
            id: UUID(),
            exerciseID: nil,
            embeddedExercise: ExerciseSnapshot(
                name: "Squat", instructions: [],
                primaryMuscles: ["Quadriceps"], equipment: ["Barbell"],
                imageURL: nil
            ),
            sets: 3, reps: 8, targetWeightKilograms: 50,
            targetRPE: nil, restSeconds: 90,
            notes: nil, targetRIR: nil, supersetGroupID: nil,
            progression: .none
        )
        var plan = emptyStrengthPlan()
        plan.exercises = [exercise]

        let store = StrengthWorkoutStore()
        store.start(
            session: plan, watchSessionID: UUID(),
            trackingMode: .advanced, captureDevice: .appleWatch
        )
        let original = try XCTUnwrap(store.activeWorkout)
        let originalIDs = original.exercises[0].sets.map(\.id)
        XCTAssertTrue(store.appendWorkoutDuringSession(intervalPlan()))
        let updated = try XCTUnwrap(store.activeWorkout)

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.watchSessionID, original.watchSessionID)
        XCTAssertEqual(updated.exercises[0].sets.map(\.id), originalIDs)
        XCTAssertFalse(updated.exercises[0].isCompleted)
        XCTAssertTrue(updated.exercises.last?.isEmbeddedRunningInterval == true)
    }

    @MainActor
    func testDistanceOnlyOutdoorRunIsRejectedWithoutMutatingSession() throws {
        let store = StrengthWorkoutStore()
        store.start(
            session: emptyStrengthPlan(), watchSessionID: UUID(),
            trackingMode: .advanced, captureDevice: .appleWatch
        )
        let original = try XCTUnwrap(store.activeWorkout)
        let distanceRun = PlannedSession(
            id: UUID(), title: "Outdoor 5 km",
            kind: .running, scheduledStart: nil,
            durationMinutes: nil, targetDistanceKilometers: 5,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        XCTAssertFalse(store.appendWorkoutDuringSession(distanceRun))
        XCTAssertEqual(store.activeWorkout?.id, original.id)
        XCTAssertEqual(store.activeWorkout?.exercises.count, 0)
    }

    @MainActor
    func testRunPhaseAutoAdvancePreservesWorkoutIdentity() throws {
        let store = StrengthWorkoutStore()
        store.start(
            session: emptyStrengthPlan(), watchSessionID: UUID(),
            trackingMode: .advanced, captureDevice: .iPhone
        )
        XCTAssertTrue(store.appendWorkoutDuringSession(intervalPlan()))
        let workoutID = try XCTUnwrap(store.activeWorkout?.id)
        store.startOrResumeTimedSet()
        let started = Date()
        store.advanceEmbeddedIntervalIfNeeded(
            at: started.addingTimeInterval(10 * 60 + 1)
        )
        XCTAssertEqual(store.activeWorkout?.id, workoutID)
        XCTAssertGreaterThanOrEqual(
            store.currentExercise?.sets.filter(\.isCompleted).count ?? 0,
            1
        )
    }
}
