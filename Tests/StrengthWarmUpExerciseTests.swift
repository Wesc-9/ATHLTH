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

    @MainActor
    func testAdvancingFromRestStartsTimedTreadmillExerciseImmediately() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        store.appendExercise(
            catalogExercise(named: "Bench Press"),
            sets: 1, reps: 8, restSeconds: 0
        )
        store.appendExercise(
            catalogExercise(named: "Treadmill Running"),
            sets: 1, reps: nil, targetKind: .time,
            targetDurationSeconds: 600, restSeconds: 0
        )
        XCTAssertNil(store.currentTimedSetCountdown)
        store.completeCurrentDraftSet()
        XCTAssertNotNil(store.nextPendingExercise)
        store.moveToNextExercise()
        XCTAssertEqual(store.currentSet?.plannedDurationSeconds, 600)
        XCTAssertNotNil(store.currentTimedSetCountdown)
        XCTAssertTrue(store.currentTimedSetCountdown?.isRunning == true)
    }

    @MainActor
    func testFinalExerciseWaitIsRestAndFreeTrainingDoesNotFakeSets() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        store.appendExercise(
            catalogExercise(named: "Bench Press"),
            sets: 1, reps: 8, restSeconds: 0
        )
        store.completeCurrentDraftSet()
        XCTAssertNotNil(store.restStartedAt)
        XCTAssertTrue(store.continueFreeTrainingBetweenExercises())
        XCTAssertTrue(store.isFreeTrainingBetweenExercises)
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 1)
        store.appendExercise(
            catalogExercise(named: "Dumbbell Curl"),
            sets: 1, reps: 8, restSeconds: 0
        )
        XCTAssertFalse(store.isFreeTrainingBetweenExercises)
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 1)
        XCTAssertNotNil(
            store.activeWorkout?.exercises.first?.sets.first?.actualRestAfterSeconds
        )
    }

    func testPlanHeartRateZoneRangesAreSharedWithLiveView() {
        XCTAssertEqual(
            ATHLTHHeartRateZones.range(for: 2, maximumBPM: 200),
            120...140
        )
        XCTAssertNil(ATHLTHHeartRateZones.range(for: 0, maximumBPM: 200))
        XCTAssertNil(ATHLTHHeartRateZones.range(for: 5, maximumBPM: nil))
    }

    @MainActor
    func testSelectedVenueAndZoneRemainAttachedToLiveWorkout() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        let place = ATHLTHTrainingPlace(
            kind: .gym, name: "Treningssenter", address: "Treningsveien 1"
        )
        store.setWorkoutTrainingPlace(place)
        store.setLiveHeartRateTargetZone(3)
        XCTAssertEqual(store.activeWorkout?.plannedTrainingPlace, place)
        XCTAssertEqual(store.activeWorkout?.liveHeartRateTargetZone, 3)
        store.setLiveHeartRateTargetZone(nil)
        XCTAssertNil(store.activeWorkout?.liveHeartRateTargetZone)
        XCTAssertEqual(store.activeWorkout?.plannedTrainingPlace, place)
    }

    @MainActor
    func testTimedHangingLSitUsesSecondsAndCanDisableWeight() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        let hold = catalogExercise(named: "Hanging L-Sit")
        store.appendExercise(hold, sets: 1, reps: nil)
        XCTAssertEqual(store.currentSet?.resolvedTargetKind, .time)
        XCTAssertFalse(store.currentSetRecordsWeight)
        store.setCurrentSetRecordsWeight(true)
        XCTAssertTrue(store.currentSetRecordsWeight)
        store.setCurrentSetRecordsWeight(false)
        store.completeCurrentDraftSet()
        let performed = try XCTUnwrap(store.activeWorkout?.exercises.first?.sets.first)
        XCTAssertNil(performed.completedWeightKilograms)
        XCTAssertNotNil(performed.completedDurationSeconds)
        XCTAssertTrue(performed.isCompleted)
    }

    @MainActor
    func testCanMoveBetweenUnfinishedSetsInDifferentExercisesWithoutCompletingOthers() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        store.appendExercise(catalogExercise(named: "Bench Press"), sets: 2, reps: 8)
        store.appendExercise(catalogExercise(named: "Dumbbell Row"), sets: 2, reps: 12)
        let logs = try XCTUnwrap(store.activeWorkout?.exercises)
        XCTAssertTrue(store.selectSetForNow(
            exerciseID: logs[1].id, setID: logs[1].sets[0].id
        ))
        store.completeCurrentDraftSet()
        XCTAssertTrue(store.selectSetForNow(
            exerciseID: logs[0].id, setID: logs[0].sets[1].id
        ))
        XCTAssertEqual(store.currentSet?.id, logs[0].sets[1].id)
        let currentLogs = try XCTUnwrap(store.activeWorkout?.exercises)
        XCTAssertTrue(currentLogs[1].sets[0].isCompleted)
        XCTAssertFalse(currentLogs[0].sets[0].isCompleted)
        XCTAssertFalse(currentLogs[0].sets[1].isCompleted)
        XCTAssertFalse(store.selectSetForNow(
            exerciseID: logs[1].id, setID: logs[1].sets[0].id
        ))
    }

    @MainActor
    func testReplayOnlyListsExercisesWithPerformedSets() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        store.appendExercise(catalogExercise(named: "Bench Press"), sets: 1, reps: 8)
        store.appendExercise(catalogExercise(named: "Row Machine"), sets: 1, reps: 8)
        store.completeCurrentDraftSet()
        let workout = try XCTUnwrap(store.activeWorkout)
        let summary = SocialPublishableWorkout.performedStrengthExerciseSummaries(workout)
        XCTAssertEqual(summary.count, 1)
        XCTAssertTrue(summary[0].contains("Bench Press"))
    }

    @MainActor
    func testWatchAcceptsNewExerciseAfterPreviousFinalSet() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        store.appendExercise(catalogExercise(named: "Row Machine"), sets: 1, reps: 10)
        store.completeCurrentDraftSet()
        let completed = try XCTUnwrap(store.watchSnapshot)
        XCTAssertTrue(completed.allExercisesComplete)

        store.appendExercise(catalogExercise(named: "Bench Press"), sets: 3, reps: 8)
        let expanded = try XCTUnwrap(store.watchSnapshot)
        XCTAssertFalse(expanded.allExercisesComplete)
        XCTAssertEqual(expanded.exerciseCount, 2)
        XCTAssertTrue(ATHLTHStrengthWatchSnapshotAcceptance.shouldApply(
            incoming: expanded, after: completed
        ))
        XCTAssertFalse(ATHLTHStrengthWatchSnapshotAcceptance.shouldApply(
            incoming: completed, after: expanded
        ))
    }

}
