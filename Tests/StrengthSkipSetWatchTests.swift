import Foundation
import XCTest
@testable import ATHLTH

final class StrengthSkipSetWatchTests: XCTestCase {
    private func exercise() -> Exercise {
        Exercise(
            id: UUID(),
            origin: .publicCatalog,
            ownerID: nil,
            name: "Squat",
            instructions: [],
            primaryMuscles: ["Quadriceps"],
            secondaryMuscles: [],
            equipment: ["Barbell"],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: true
        )
    }

    @MainActor
    func testSkippingPendingSetDoesNotCreateTrainingVolume() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: UUID(), captureDevice: .appleWatch)
        store.appendExercise(exercise(), sets: 3, reps: 8)
        XCTAssertEqual(store.watchSnapshot?.setCount, 3)
        XCTAssertTrue(store.skipCurrentSet())
        XCTAssertEqual(store.watchSnapshot?.setCount, 2)
        XCTAssertEqual(store.watchSnapshot?.skippedSets, 1)
        XCTAssertEqual(store.watchSnapshot?.totalSets, 3)
        XCTAssertEqual(store.watchSnapshot?.completedSets, 0)
        XCTAssertEqual(store.activeWorkout?.exercises[0].skippedPlannedSetCount, 1)
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 0)
        XCTAssertEqual(store.activeWorkout?.exercises[0].sets.reduce(0.0) {
            $0 + $1.volumeKilograms
        }, 0)
    }

    @MainActor
    func testSkippingTheOnlySetFinishesExerciseButDoesNotRecordASet() {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: UUID(), captureDevice: .appleWatch)
        store.appendExercise(exercise(), sets: 1, reps: 8)
        XCTAssertTrue(store.skipCurrentSet())
        XCTAssertTrue(store.currentExerciseAllSetsCompleted)
        XCTAssertEqual(store.activeWorkout?.exercises[0].skippedPlannedSetCount, 1)
        XCTAssertTrue(store.activeWorkout?.exercises[0].sets.isEmpty == true)
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 0)
    }

    @MainActor
    func testCompletedSetCannotBeSkippedAgain() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: UUID(), captureDevice: .appleWatch)
        store.appendExercise(exercise(), sets: 1, reps: 8)
        store.completeCurrentDraftSet()
        XCTAssertFalse(store.skipCurrentSet())
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 1)
        XCTAssertEqual(store.watchSnapshot?.skippedSets, 0)
    }

    func testWatchCanSkipSetEvenWhenIPhoneOwnsDraftValues() {
        XCTAssertTrue(ATHLTHStrengthWatchControlPolicy.permits(
            .skipSet, whenIPhoneControls: true
        ))
        XCTAssertFalse(ATHLTHStrengthWatchControlPolicy.permits(
            .updateDraft, whenIPhoneControls: true
        ))
    }

    func testPhoneCapturedWorkoutAllowsWatchSetLoggingForBothAndWatchModes() {
        XCTAssertTrue(ATHLTHStrengthWatchControlPolicy.acceptsSetCommands(
            captureDevice: .iPhone, inputMode: .both
        ))
        XCTAssertTrue(ATHLTHStrengthWatchControlPolicy.acceptsSetCommands(
            captureDevice: .iPhone, inputMode: .appleWatch
        ))
        XCTAssertFalse(ATHLTHStrengthWatchControlPolicy.acceptsSetCommands(
            captureDevice: .iPhone, inputMode: .iPhone
        ))
        XCTAssertTrue(ATHLTHStrengthWatchControlPolicy.acceptsSetCommands(
            captureDevice: .appleWatch, inputMode: .both
        ))
    }
    @MainActor
    func testSixInchHoldUsesUnweightedOpenEndedStopwatch() {
        var hold = exercise()
        hold.name = "Six Inch Hold"
        hold.equipment = ["Bodyweight"]
        XCTAssertEqual(hold.snapshot.defaultStrengthTargetKind, .time)
        XCTAssertTrue(hold.snapshot.isTimeOnlyBodyweightStrength)

        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: UUID(), captureDevice: .appleWatch)
        store.appendExercise(
            hold, sets: 1, reps: nil, targetKind: .time,
            targetDurationSeconds: nil, restSeconds: 0,
            openEndedTime: true
        )

        XCTAssertEqual(store.currentSet?.targetKind, .time)
        XCTAssertNil(store.currentSet?.plannedDurationSeconds)
        XCTAssertEqual(store.currentSet?.recordsWeight, false)
        XCTAssertEqual(store.watchSnapshot?.isOpenEndedTimedSet, true)

        store.startOrResumeTimedSet(at: Date(timeIntervalSinceNow: -11))
        XCTAssertNotNil(store.currentSetEffortClock)
        XCTAssertNil(store.currentTimedSetCountdown)
        store.completeCurrentDraftSet()
        XCTAssertEqual(store.activeWorkout?.totalVolumeKilograms, 0)
        XCTAssertGreaterThanOrEqual(
            store.currentSet?.completedDurationSeconds ?? 0, 10
        )
    }

    @MainActor
    func testDynamicPlankRemainsRepBasedAndHistoryIsNotReinterpreted() {
        var dynamic = exercise()
        dynamic.name = "Plank Shoulder Taps"
        dynamic.equipment = ["Bodyweight"]
        XCTAssertFalse(dynamic.snapshot.isTimeOnlyBodyweightStrength)
        XCTAssertEqual(dynamic.snapshot.defaultStrengthTargetKind, .reps)
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        store.appendExercise(dynamic, sets: 1, reps: 12)
        let original = try? XCTUnwrap(store.activeWorkout)
        let repaired = StrengthTimedHistoryRepair.clean(original.map { [$0] } ?? [])
        XCTAssertFalse(repaired.changed)
    }

    @MainActor
    func testHistoricFalseCoreWeightIsNotTurnedIntoInventedTime() {
        var hold = exercise()
        hold.name = "Six Inch Hold"
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        store.appendExercise(hold, sets: 1, reps: 12)
        guard var log = store.activeWorkout else {
            return XCTFail("Expected active workout")
        }
        log.exercises[0].sets[0].completedAt = Date()
        log.exercises[0].sets[0].completedReps = 12
        log.exercises[0].sets[0].completedWeightKilograms = 20
        log.exercises[0].sets[0].actualSetElapsedSeconds = nil
        let removed = StrengthTimedHistoryRepair.clean([log])
        XCTAssertTrue(removed.changed)
        XCTAssertTrue(removed.history[0].exercises.isEmpty)

        log.exercises[0].sets[0].actualSetElapsedSeconds = 42
        let preserved = StrengthTimedHistoryRepair.clean([log])
        XCTAssertTrue(preserved.changed)
        XCTAssertEqual(
            preserved.history[0].exercises[0].sets[0].completedDurationSeconds,
            42
        )
        XCTAssertNil(preserved.history[0].exercises[0].sets[0].completedReps)
        XCTAssertNil(
            preserved.history[0].exercises[0].sets[0].completedWeightKilograms
        )
    }

    func testStartSetCommandWorksWithBothDevicesAndIPhoneControlledDraft() {
        XCTAssertTrue(ATHLTHStrengthWatchControlPolicy.permits(
            .startSetEffort, whenIPhoneControls: true
        ))
        XCTAssertFalse(ATHLTHStrengthWatchControlPolicy.permits(
            .updateDraft, whenIPhoneControls: true
        ))
    }

}
