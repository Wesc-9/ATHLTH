import Foundation
import XCTest
@testable import ATHLTH

final class StrengthWarmUpExerciseTests: XCTestCase {
    private func exercise() -> PlannedExercise {
        PlannedExercise(
            id: UUID(),
            exerciseID: nil,
            embeddedExercise: ExerciseSnapshot(
                name: "Warm-up row",
                instructions: [],
                primaryMuscles: ["Back"],
                secondaryMuscles: [],
                equipment: ["Cable"],
                imageURL: nil
            ),
            sets: 3,
            reps: 12,
            targetWeightKilograms: nil,
            targetRPE: nil,
            restSeconds: 60,
            notes: nil,
            targetRIR: nil,
            supersetGroupID: nil,
            progression: .none
        )
    }

    func testExerciseWarmUpClassifiesEveryPlannedSetAndCanBeReverted() throws {
        var planned = exercise()
        XCTAssertFalse(planned.isWarmUpExercise)

        planned.setEntireExerciseWarmUp(true)
        XCTAssertTrue(planned.isWarmUpExercise)
        XCTAssertEqual(planned.resolvedSetTargets.count, 3)
        XCTAssertTrue(planned.resolvedSetTargets.allSatisfy {
            $0.isWarmUp == true && $0.setType == .warmUp
        })

        let restored = try JSONDecoder().decode(
            PlannedExercise.self,
            from: JSONEncoder().encode(planned)
        )
        XCTAssertTrue(restored.isWarmUpExercise)
        XCTAssertEqual(restored.resolvedSetTargets.map(\.reps), [12, 12, 12])

        planned.setEntireExerciseWarmUp(false)
        XCTAssertFalse(planned.isWarmUpExercise)
        XCTAssertTrue(planned.resolvedSetTargets.allSatisfy {
            $0.isWarmUp == false && $0.setType == .work
        })
    }

    func testPartialWarmUpRemainsAWorkingExercise() {
        var planned = exercise()
        planned.setTargets = [
            PlannedExerciseSetTarget(reps: 8, isWarmUp: true, setType: .warmUp),
            PlannedExerciseSetTarget(reps: 10, isWarmUp: false, setType: .work),
            PlannedExerciseSetTarget(reps: 10, isWarmUp: false, setType: .work)
        ]
        XCTAssertFalse(planned.isWarmUpExercise)
        planned.setEntireExerciseWarmUp(true)
        XCTAssertTrue(planned.isWarmUpExercise)
        XCTAssertEqual(planned.resolvedSetTargets.map(\.reps), [8, 10, 10])
    }

    func testCompletedWarmUpSetDoesNotCountTowardTrainingLoad() {
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        var first = StrengthSetLog(
            id: UUID(),
            setNumber: 1,
            plannedReps: 10,
            plannedWeightKilograms: 10,
            completedReps: 10,
            completedWeightKilograms: 10,
            rpe: nil,
            completedAt: date,
            restSeconds: 45
        )
        first.isWarmUp = true
        first.plannedSetType = .warmUp
        XCTAssertFalse(first.countsTowardTrainingLoad)

        var second = first
        second.isWarmUp = false
        second.plannedSetType = .work
        XCTAssertTrue(second.countsTowardTrainingLoad)
    }
    private func catalogExercise(named name: String) -> Exercise {
        Exercise(
            id: UUID(), origin: .publicCatalog, ownerID: nil,
            name: name, instructions: ["Warm up at a comfortable pace."],
            primaryMuscles: ["Quadriceps"], secondaryMuscles: [],
            equipment: ["Treadmill"], imageURL: nil
        )
    }

    func testTreadmillWarmUpStartsWithOneTenMinuteTimedSet() {
        let planned = StrengthTreadmillWarmUpDefaults.plannedExercise(
            for: catalogExercise(named: "Treadmill Running")
        )
        XCTAssertEqual(planned.sets, 1)
        XCTAssertEqual(planned.resolvedTargetKind, .time)
        XCTAssertEqual(planned.resolvedTargetDurationSeconds, 600)
        XCTAssertEqual(planned.resolvedSetTargets.count, 1)
        XCTAssertEqual(planned.resolvedSetTargets.first?.durationSeconds, 600)
        XCTAssertTrue(planned.isWarmUpExercise)
    }

    func testNorwegianTreadmillWarmUpGetsSameDefaults() {
        let planned = StrengthTreadmillWarmUpDefaults.plannedExercise(
            for: catalogExercise(named: "Tredemølle Running")
        )
        XCTAssertEqual(planned.sets, 1)
        XCTAssertEqual(planned.resolvedTargetDurationSeconds, 600)
        XCTAssertTrue(planned.isWarmUpExercise)
    }

    func testStandardStrengthExerciseKeepsOriginalDefaults() {
        let planned = StrengthTreadmillWarmUpDefaults.plannedExercise(
            for: catalogExercise(named: "Dumbbell Curl")
        )
        XCTAssertEqual(planned.sets, 3)
        XCTAssertEqual(planned.reps, 8)
        XCTAssertFalse(planned.isWarmUpExercise)
    }

    @MainActor
    func testSkippingRemainingSetsKeepsCompletedWorkAndRecordsOmissions() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        let exercise = Exercise(
            id: UUID(), origin: .publicCatalog, ownerID: nil,
            name: "Bench Press", instructions: ["Control each repetition."],
            primaryMuscles: ["Chest"], secondaryMuscles: [],
            equipment: ["Barbell"], imageURL: nil
        )
        store.appendExercise(exercise, sets: 3, reps: 8, restSeconds: 0)
        store.completeCurrentDraftSet()
        store.completeCurrentDraftSet()
        XCTAssertEqual(store.activeWorkout?.exercises.first?.sets.count, 3)

        XCTAssertTrue(store.omitRemainingSetsOfCurrentExercise())
        let stored = try XCTUnwrap(store.activeWorkout?.exercises.first)
        XCTAssertEqual(stored.sets.count, 2)
        XCTAssertEqual(stored.sets.filter(\.isCompleted).count, 2)
        XCTAssertEqual(stored.skippedPlannedSetCount, 1)
        XCTAssertTrue(store.currentExerciseAllSetsCompleted)
        XCTAssertFalse(store.omitRemainingSetsOfCurrentExercise())
    }

    @MainActor
    func testManualTreadmillSpeedInclineAndEstimatedDistancePersistOnSet() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        let treadmill = Exercise(
            id: UUID(), origin: .publicCatalog, ownerID: nil,
            name: "Treadmill Running", instructions: ["Comfortable pace."],
            primaryMuscles: ["Quadriceps"], secondaryMuscles: [],
            equipment: ["Treadmill"], imageURL: nil
        )
        store.appendExercise(
            treadmill, sets: 1, reps: nil, targetKind: .time,
            targetDurationSeconds: 600, restSeconds: 0, warmUpSets: 1
        )
        store.setDraft(
            treadmillSpeedKilometersPerHour: 9.0, treadmillInclinePercent: 2.5
        )
        store.completeCurrentDraftSet()
        let set = try XCTUnwrap(store.activeWorkout?.exercises.first?.sets.first)
        XCTAssertEqual(set.completedDurationSeconds, 600)
        XCTAssertEqual(set.completedTreadmillSpeedKilometersPerHour, 9.0)
        XCTAssertEqual(set.completedTreadmillInclinePercent, 2.5)
        XCTAssertEqual(
            try XCTUnwrap(set.manuallyEstimatedTreadmillDistanceMeters),
            1_500, accuracy: 0.01
        )
        XCTAssertNil(set.completedDistanceMeters)
        XCTAssertNil(set.completedWeightKilograms)
        XCTAssertTrue(set.isWarmUp == true)
    }

}
