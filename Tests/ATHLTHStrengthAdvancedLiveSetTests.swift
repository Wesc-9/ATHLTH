import Foundation
import XCTest
@testable import ATHLTH

/// Exercise drafts stay in the existing recording store; the shared live
/// dock must not add a shadow set, round, or HealthKit workout.
@MainActor
final class ATHLTHStrengthAdvancedLiveSetTests: XCTestCase {
    private func makeExercise(_ name: String = "Bench Press") -> Exercise {
        Exercise(
            id: UUID(),
            origin: .publicCatalog,
            ownerID: nil,
            name: name,
            instructions: ["Control the movement."],
            primaryMuscles: ["Chest"],
            secondaryMuscles: [],
            equipment: ["Barbell"],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: true
        )
    }

    func testAdvancedRPEAndWarmUpAreWrittenOnceToOriginalSet() throws {
        var config = StrengthAdvancedConfiguration.standard
        config.effortMetric = .rpe
        let store = StrengthWorkoutStore()
        store.startFreestyle(
            watchSessionID: nil, trackingMode: .advanced,
            captureDevice: .iPhone, advancedConfiguration: config
        )
        store.appendExercise(makeExercise(), sets: 1, reps: 8, restSeconds: 0)
        let workoutID = try XCTUnwrap(store.activeWorkout?.id)
        let exerciseID = try XCTUnwrap(store.currentExercise?.id)
        let setID = try XCTUnwrap(store.currentSet?.id)

        store.setDraft(reps: 9, weightKilograms: 50, rpe: 9.5, warmUp: true)
        store.completeCurrentDraftSet()

        let workout = try XCTUnwrap(store.activeWorkout)
        let performed = try XCTUnwrap(workout.exercises.first?.sets.first)
        XCTAssertEqual(workout.id, workoutID)
        XCTAssertEqual(workout.exercises.first?.id, exerciseID)
        XCTAssertEqual(performed.id, setID)
        XCTAssertEqual(performed.completedReps, 9)
        XCTAssertEqual(performed.completedWeightKilograms, 50)
        XCTAssertEqual(performed.rpe, 9.5)
        XCTAssertNil(performed.rir)
        XCTAssertEqual(performed.isWarmUp, true)
        XCTAssertFalse(performed.countsTowardTrainingLoad)
        XCTAssertEqual(workout.totalCompletedSets, 1)
    }

    func testRIRUsesConfiguredMetricAndDoesNotCreateRPEDuplicate() throws {
        var config = StrengthAdvancedConfiguration.standard
        config.effortMetric = .rir
        let store = StrengthWorkoutStore()
        store.startFreestyle(
            watchSessionID: nil, trackingMode: .advanced,
            captureDevice: .iPhone, advancedConfiguration: config
        )
        store.appendExercise(makeExercise(), sets: 1, reps: 10, restSeconds: 0)
        store.setDraft(rir: 1.5, warmUp: false)
        store.completeCurrentDraftSet()
        let performed = try XCTUnwrap(store.activeWorkout?.exercises.first?.sets.first)
        XCTAssertEqual(performed.rir, 1.5)
        XCTAssertNil(performed.rpe)
        XCTAssertEqual(performed.isWarmUp, false)
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 1)
    }

    func testTimedStrengthDraftKeepsSecondsAndSetIdentity() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        store.appendExercise(
            makeExercise("Plank Hold"), sets: 1, reps: nil,
            targetKind: .time, targetDurationSeconds: 45,
            restSeconds: 0
        )
        let id = try XCTUnwrap(store.currentSet?.id)
        XCTAssertEqual(store.currentSet?.plannedDurationSeconds, 45)
        store.setDraft(durationSeconds: 30)
        XCTAssertEqual(store.draftDurationSeconds, 30)
        XCTAssertEqual(store.currentSet?.id, id)
        store.completeCurrentDraftSet()
        let completed = try XCTUnwrap(store.activeWorkout?.exercises.first?.sets.first)
        XCTAssertEqual(completed.id, id)
        XCTAssertEqual(completed.completedDurationSeconds, 30)
    }
}
