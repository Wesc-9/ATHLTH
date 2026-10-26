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

    func testWarmUpPhaseAndTimedPrescriptionSurvivePlanSerialization() throws {
        var planned = exercise()
        planned.targetKind = .time
        planned.targetDurationSeconds = 45
        planned.reps = nil
        planned.setEntireExerciseWarmUp(true)
        planned.workoutPhase = .warmup

        let restored = try JSONDecoder().decode(
            PlannedExercise.self, from: JSONEncoder().encode(planned)
        )
        XCTAssertEqual(restored.workoutPhase, .warmup)
        XCTAssertTrue(restored.isWarmUpExercise)
        XCTAssertEqual(restored.resolvedTargetKind, .time)
        XCTAssertEqual(restored.resolvedSetTargets.map(\.durationSeconds),
                       [45, 45, 45])
    }

    func testNinetyNinetyHoldIsTimedByDefault() {
        let snapshot = ExerciseSnapshot(
            name: "90/90 hold",
            instructions: [],
            primaryMuscles: ["Hip flexors"],
            secondaryMuscles: [],
            equipment: ["Bodyweight"],
            imageURL: nil
        )
        XCTAssertEqual(snapshot.defaultStrengthTargetKind, .time)
        XCTAssertTrue(StrengthTimedBodyweightDefaults.isBodyweightHold("90/90 hold"))
        XCTAssertFalse(StrengthTimedBodyweightDefaults.isBodyweightHold("90/90 hip switches"))
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
        let equipment: [String]
        if StrengthTreadmillWarmUpDefaults.isTreadmill(name) {
            equipment = ["Treadmill"]
        } else if StrengthCardioExercisePolicy.isCardio(name) {
            equipment = ["Rowing machine"]
        } else if name.localizedCaseInsensitiveContains("dumbbell") {
            equipment = ["Dumbbell"]
        } else if name.localizedCaseInsensitiveContains("bench press") {
            equipment = ["Barbell"]
        } else {
            equipment = ["Bodyweight"]
        }
        return Exercise(
            id: UUID(), origin: .publicCatalog, ownerID: nil,
            name: name, instructions: ["Warm up at a comfortable pace."],
            primaryMuscles: ["Quadriceps"], secondaryMuscles: [],
            equipment: equipment, imageURL: nil,
            isVisibleOutsideOwnerLibrary: true
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
            equipment: ["Barbell"], imageURL: nil,
            isVisibleOutsideOwnerLibrary: true
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
            equipment: ["Treadmill"], imageURL: nil,
            isVisibleOutsideOwnerLibrary: true
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

    private func cardioWatchSample(
        startedAt: Date, capturedAt: Date,
        elapsed: Double, meters: Double, pulse: Double = 132,
        freshPulse: Bool = true
    ) -> WatchWorkoutLiveSnapshot {
        WatchWorkoutLiveSnapshot(
            kind: .strength,
            state: .running,
            startedAt: startedAt,
            capturedAt: capturedAt,
            elapsedTime: elapsed,
            heartRate: pulse,
            activeCalories: 15,
            distanceMeters: meters,
            averageHeartRate: nil,
            maxHeartRate: nil,
            routePointCount: 0,
            coachHeartRateSampleAt: freshPulse ? capturedAt : nil
        )
    }

    func testWatchCardioCaptureDoesNotConvertEstimatesIntoMeasurements() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = cardioWatchSample(
            startedAt: start,
            capturedAt: start.addingTimeInterval(5),
            elapsed: 5, meters: 100, pulse: 130
        )
        var capture = StrengthWatchCardioCapture(
            watchWorkoutStartedAt: start,
            lastCapturedAt: first.capturedAt,
            lastElapsedTime: first.elapsedTime,
            lastDistanceMeters: first.distanceMeters
        )
        capture.recordHeartRate(from: first)
        let second = cardioWatchSample(
            startedAt: start,
            capturedAt: start.addingTimeInterval(10),
            elapsed: 10, meters: 125, pulse: 140
        )
        capture.ingest(second)
        capture.ingest(second)
        XCTAssertEqual(capture.measuredDistanceMeters, 25, accuracy: 0.001)
        XCTAssertEqual(capture.capturedActiveDuration, 5, accuracy: 0.001)
        XCTAssertEqual(capture.averageHeartRate ?? 0, 135, accuracy: 0.001)
        XCTAssertEqual(capture.heartRateSampleCount, 2)

        // A delayed or disconnected Watch sample must not inflate metrics.
        capture.ingest(cardioWatchSample(
            startedAt: start, capturedAt: start.addingTimeInterval(80),
            elapsed: 80, meters: 300, pulse: 160, freshPulse: false
        ))
        XCTAssertEqual(capture.measuredDistanceMeters, 25, accuracy: 0.001)
        XCTAssertEqual(capture.capturedActiveDuration, 5, accuracy: 0.001)
        XCTAssertEqual(capture.heartRateSampleCount, 2)
    }

    @MainActor
    func testWatchMetricsAttachOnlyToCardioSetAndKeepManualProvenance() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(
            watchSessionID: UUID(), captureDevice: .appleWatch
        )
        store.appendExercise(
            catalogExercise(named: "Treadmill Running"),
            sets: 1, reps: nil, targetKind: .time,
            targetDurationSeconds: 600, restSeconds: 0, warmUpSets: 1
        )
        store.setDraft(treadmillSpeedKilometersPerHour: 9.0,
                       treadmillInclinePercent: 2)
        let mirrored = try XCTUnwrap(store.watchSnapshot)
        XCTAssertEqual(mirrored.manualTreadmillSpeedKilometersPerHour, 9.0)
        XCTAssertEqual(mirrored.manualTreadmillInclinePercent, 2)
        // Wire values travel with the already active Watch strength session.
        let encoded = try JSONEncoder().encode(mirrored)
        let decoded = try JSONDecoder().decode(
            WatchStrengthSessionSnapshot.self, from: encoded
        )
        XCTAssertEqual(decoded.manualTreadmillSpeedKilometersPerHour, 9.0)
        XCTAssertEqual(decoded.manualTreadmillInclinePercent, 2)
        store.startOrResumeTimedSet()
        let started = try XCTUnwrap(store.activeWorkout?.startedAt)
        store.ingestWatchCardioSnapshot(cardioWatchSample(
            startedAt: started,
            capturedAt: started.addingTimeInterval(3), elapsed: 3,
            meters: 100, pulse: 130
        ))
        store.ingestWatchCardioSnapshot(cardioWatchSample(
            startedAt: started,
            capturedAt: started.addingTimeInterval(8), elapsed: 8,
            meters: 127, pulse: 140
        ))
        store.completeCurrentSet(
            reps: nil, durationSeconds: 60, weightKilograms: nil, rpe: nil,
            isWarmUp: true
        )
        let set = try XCTUnwrap(store.activeWorkout?.exercises.first?.sets.first)
        XCTAssertEqual(set.watchMeasuredDistanceMeters ?? 0, 27, accuracy: 0.001)
        XCTAssertEqual(set.watchActiveDurationSeconds ?? 0, 5, accuracy: 0.001)
        XCTAssertEqual(set.watchAverageHeartRateBPM ?? 0, 135, accuracy: 0.001)
        XCTAssertEqual(set.completedTreadmillSpeedKilometersPerHour, 9.0)
        XCTAssertEqual(set.completedTreadmillInclinePercent, 2)
        XCTAssertEqual(set.completedDistanceMeters ?? 0, 27, accuracy: 0.001)
        XCTAssertNotNil(set.manuallyEstimatedTreadmillDistanceMeters)
        XCTAssertEqual(store.activeWorkout?.totalVolumeKilograms, 0)
        XCTAssertEqual(store.workoutHistory.count, 0) // No duplicate workout.
    }

    @MainActor
    func testCombinedReplayKeepsWarmUpSeparateFromLiftingVolume() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        store.appendExercise(
            catalogExercise(named: "Bench Press"), sets: 2, reps: 8,
            targetWeightKilograms: 100, restSeconds: 0, warmUpSets: 1
        )
        store.setDraft(weightKilograms: 100)
        store.completeCurrentDraftSet()
        store.setDraft(weightKilograms: 100)
        store.completeCurrentDraftSet()
        store.appendExercise(
            catalogExercise(named: "Treadmill Running"), sets: 1,
            reps: nil, targetKind: .time, targetDurationSeconds: 600,
            restSeconds: 0, warmUpSets: 1
        )
        store.setDraft(treadmillSpeedKilometersPerHour: 9,
                       treadmillInclinePercent: 1.5)
        store.completeCurrentDraftSet()
        let workout = try XCTUnwrap(store.activeWorkout)
        let replay = SocialPublishableWorkout(strengthWorkout: workout)
        XCTAssertEqual(replay.strengthTotalVolumeKilograms ?? 0, 800, accuracy: 0.001)
        XCTAssertEqual(replay.strengthHeaviestWeightKilograms ?? 0, 100)
        XCTAssertEqual(replay.strengthCardioDurationSeconds, 600)
        XCTAssertEqual(replay.strengthCardioExerciseCount, 1)
        XCTAssertNil(replay.strengthCardioMeasuredMeters)
        XCTAssertNotNil(replay.strengthCardioEstimatedMeters)
        XCTAssertEqual(replay.strengthPerformedExerciseSummaries?.count, 2)
    }


    func testRowingMachineIsCardioButResistanceRowsRemainStrength() {
        XCTAssertTrue(StrengthCardioExercisePolicy.isCardio("Row Machine"))
        XCTAssertTrue(StrengthCardioExercisePolicy.isCardio("Rowing machine"))
        XCTAssertTrue(StrengthCardioExercisePolicy.isCardio("Romaskin"))
        XCTAssertTrue(StrengthCardioExercisePolicy.isCardio("Tredemølle"))
        XCTAssertFalse(StrengthCardioExercisePolicy.isCardio("Dumbbell Rowing"))
        XCTAssertFalse(StrengthCardioExercisePolicy.isCardio("Bent Over Rowing"))
        XCTAssertFalse(StrengthCardioExercisePolicy.isCardio("Seated Cable Row"))
        XCTAssertFalse(StrengthCardioExercisePolicy.isCardio("Seated Row Machine"))
    }

    @MainActor
    func testResistanceRowStillCountsTowardLiftingVolume() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        store.appendExercise(
            catalogExercise(named: "Dumbbell Rowing"),
            sets: 1, reps: 8, targetWeightKilograms: 40, restSeconds: 0
        )
        store.setDraft(weightKilograms: 40)
        store.completeCurrentDraftSet()
        let workout = try XCTUnwrap(store.activeWorkout)
        let replay = SocialPublishableWorkout(strengthWorkout: workout)
        XCTAssertEqual(replay.strengthTotalVolumeKilograms ?? 0, 320, accuracy: 0.001)
        XCTAssertNil(replay.strengthCardioExerciseCount)
    }

    @MainActor
    func testMixedWatchAndManualDistanceOnlyCountsEachSetOnce() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: UUID(), captureDevice: .appleWatch)
        store.appendExercise(
            catalogExercise(named: "Treadmill Running"),
            sets: 2, reps: nil, targetKind: .time,
            targetDurationSeconds: 60, restSeconds: 0, warmUpSets: 2
        )
        store.setDraft(treadmillSpeedKilometersPerHour: 9, treadmillInclinePercent: 2)
        store.startOrResumeTimedSet()
        let started = try XCTUnwrap(store.activeWorkout?.startedAt)
        store.ingestWatchCardioSnapshot(cardioWatchSample(
            startedAt: started, capturedAt: started.addingTimeInterval(4),
            elapsed: 4, meters: 100, pulse: 130
        ))
        store.ingestWatchCardioSnapshot(cardioWatchSample(
            startedAt: started, capturedAt: started.addingTimeInterval(9),
            elapsed: 9, meters: 127, pulse: 140
        ))
        store.completeCurrentSet(
            reps: nil, durationSeconds: 60, weightKilograms: nil,
            rpe: nil, isWarmUp: true
        )

        store.setDraft(treadmillSpeedKilometersPerHour: 9, treadmillInclinePercent: 2)
        store.completeCurrentSet(
            reps: nil, durationSeconds: 60, weightKilograms: nil,
            rpe: nil, isWarmUp: true
        )
        let workout = try XCTUnwrap(store.activeWorkout)
        let replay = SocialPublishableWorkout(strengthWorkout: workout)
        XCTAssertEqual(replay.strengthCardioMeasuredMeters ?? 0, 27, accuracy: 0.001)
        // Only the second set falls back to 9 km/h × 60 sec = 150 m.
        XCTAssertEqual(replay.strengthCardioEstimatedMeters ?? 0, 150, accuracy: 0.001)
        XCTAssertEqual(replay.strengthCardioDurationSeconds, 120)
        XCTAssertEqual(workout.totalVolumeKilograms, 0)
        XCTAssertTrue(workout.exercises[0].sets[0].manuallyEstimatedTreadmillDistanceMeters != nil)
    }

}
