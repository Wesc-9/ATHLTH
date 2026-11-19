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
    func testReduceThreeSetsToOneKeepsTheOnlyCompletedSet() {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: UUID(), captureDevice: .appleWatch)
        store.appendExercise(exercise(), sets: 3, reps: 8, restSeconds: 0)

        let exerciseID = try! XCTUnwrap(store.activeWorkout?.exercises.first?.id)
        let firstID = try! XCTUnwrap(store.activeWorkout?.exercises.first?.sets.first?.id)
        store.completeCurrentDraftSet()
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 1)
        XCTAssertEqual(store.watchSnapshot?.setCount, 3)

        XCTAssertTrue(store.adjustActiveExerciseSetCount(exerciseID, to: 1))
        XCTAssertEqual(store.activeWorkout?.exercises[0].sets.count, 1)
        XCTAssertEqual(store.activeWorkout?.exercises[0].sets[0].id, firstID)
        XCTAssertTrue(store.activeWorkout?.exercises[0].sets[0].isCompleted == true)
        XCTAssertEqual(store.activeWorkout?.exercises[0].skippedPlannedSetCount ?? 0, 0)
        XCTAssertTrue(store.currentExerciseAllSetsCompleted)
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 1)
        XCTAssertEqual(store.watchSnapshot?.setCount, 1)
        XCTAssertEqual(store.watchSnapshot?.totalSets, 1)
        XCTAssertEqual(store.watchSnapshot?.completedSets, 1)
    }

    @MainActor
    func testErroneouslyCompletedSetsNeedExplicitCorrection() {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: UUID(), captureDevice: .appleWatch)
        store.appendExercise(exercise(), sets: 3, reps: 8, restSeconds: 0)
        let exerciseID = try! XCTUnwrap(store.activeWorkout?.exercises.first?.id)
        let firstID = try! XCTUnwrap(store.activeWorkout?.exercises.first?.sets.first?.id)

        for _ in 0..<3 {
            store.completeCurrentDraftSet()
        }
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 3)

        XCTAssertFalse(store.adjustActiveExerciseSetCount(exerciseID, to: 1))
        XCTAssertEqual(store.activeWorkout?.exercises[0].sets.count, 3)
        XCTAssertTrue(store.adjustActiveExerciseSetCount(
            exerciseID, to: 1, correctRecordedSets: true
        ))
        XCTAssertEqual(store.activeWorkout?.exercises[0].sets.map(\.id), [firstID])
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 1)
        XCTAssertEqual(store.watchSnapshot?.totalSets, 1)
        XCTAssertEqual(store.watchSnapshot?.completedSets, 1)
    }

    @MainActor
    func testIncreasingSetsCreatesPendingSetWithoutDuplicatingResults() {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: UUID(), captureDevice: .iPhone)
        store.appendExercise(exercise(), sets: 2, reps: 10, restSeconds: 0)
        let exerciseID = try! XCTUnwrap(store.activeWorkout?.exercises.first?.id)
        store.completeCurrentDraftSet()
        let firstID = try! XCTUnwrap(store.activeWorkout?.exercises.first?.sets.first?.id)

        XCTAssertTrue(store.adjustActiveExerciseSetCount(exerciseID, to: 1))
        XCTAssertTrue(store.adjustActiveExerciseSetCount(exerciseID, to: 2))

        let sets = store.activeWorkout?.exercises.first?.sets ?? []
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[0].id, firstID)
        XCTAssertNotEqual(sets[1].id, firstID)
        XCTAssertTrue(sets[0].isCompleted)
        XCTAssertFalse(sets[1].isCompleted)
        XCTAssertEqual(sets[1].setNumber, 2)
        XCTAssertEqual(sets[1].plannedReps, 10)
        XCTAssertNil(sets[1].completedReps)
        XCTAssertEqual(store.currentSet?.id, sets[1].id)
        XCTAssertEqual(store.watchSnapshot?.setNumber, 2)
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 1)
        XCTAssertFalse(store.currentExerciseAllSetsCompleted)
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


    @MainActor
    func testOfflineWatchBootstrapCannotCrossAccountsOrUseLegacyUnownedRequest() throws {
        let owner = UUID()
        let recording = StrengthWorkoutStore()
        recording.startFreestyle(watchSessionID: nil, captureDevice: .appleWatch)
        let snapshot = try XCTUnwrap(recording.watchSnapshot)
        let workoutID = snapshot.workoutID
        var command = WatchStrengthCommand(
            id: UUID(), workoutID: workoutID, kind: .requestSnapshot,
            reps: nil, weightKilograms: nil, restSeconds: nil,
            addRestSeconds: nil, sentAt: Date(),
            initiatedOnWatch: true
        )
        XCTAssertFalse(ATHLTHStrengthWatchBootstrapOwnershipPolicy.permitsBootstrap(
            command, currentAccountID: owner
        ))
        command.accountOwnerID = owner
        XCTAssertFalse(ATHLTHStrengthWatchBootstrapOwnershipPolicy.permitsBootstrap(
            command, currentAccountID: owner
        ), "A Watch UUID without its original state cannot bootstrap a replacement.")
        command.bootstrapSnapshot = snapshot
        XCTAssertTrue(ATHLTHStrengthWatchBootstrapOwnershipPolicy.permitsBootstrap(
            command, currentAccountID: owner
        ))
        XCTAssertFalse(ATHLTHStrengthWatchBootstrapOwnershipPolicy.permitsBootstrap(
            command, currentAccountID: UUID()
        ))
        command.workoutID = nil
        XCTAssertFalse(ATHLTHStrengthWatchBootstrapOwnershipPolicy.permitsBootstrap(
            command, currentAccountID: owner
        ))

        // Legacy Watch payloads without accountOwnerID still decode.
        command.workoutID = workoutID
        let encoded = try JSONEncoder().encode(command)
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacy.removeValue(forKey: "accountOwnerID")
        let restored = try JSONDecoder().decode(
            WatchStrengthCommand.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertNil(restored.accountOwnerID)
        XCTAssertFalse(ATHLTHStrengthWatchBootstrapOwnershipPolicy.permitsBootstrap(
            restored, currentAccountID: owner
        ))
    }



    @MainActor
    func testWatchStrengthStoreIsAccountReadyOnlyAfterScopedRestore() {
        let owner = UUID()
        let other = UUID()
        let store = StrengthWorkoutStore()
        XCTAssertFalse(store.isLoaded(for: owner))
        store.switchAccount(owner)
        XCTAssertTrue(store.isLoaded(for: owner))
        XCTAssertFalse(store.isLoaded(for: other))
        store.switchAccount(nil)
        XCTAssertFalse(store.isLoaded(for: owner))
    }

    @MainActor
    func testWatchBootstrapDoesNotOverwriteExistingStrengthWorkout() throws {
        let userID = UUID()
        defer {
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthActive", userID: userID)
            )
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthHistory", userID: userID)
            )
            StrengthWorkoutCompletionJournal.remove(userID: userID)
        }
        let store = StrengthWorkoutStore()
        store.switchAccount(userID)
        store.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        let existingID = try XCTUnwrap(store.activeWorkout?.id)
        var competing = try XCTUnwrap(store.watchSnapshot)
        competing.workoutID = UUID()
        XCTAssertFalse(store.startFromWatchSnapshot(competing))
        XCTAssertEqual(store.activeWorkout?.id, existingID)
    }

    @MainActor
    func testWatchBootstrapAdmissionRejectsOccupiedAndCompletedSlots() throws {
        let userID = UUID()
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil, captureDevice: .appleWatch)
        let snapshot = try XCTUnwrap(store.watchSnapshot)
        XCTAssertTrue(ATHLTHStrengthWatchBootstrapAdmissionPolicy.canRestore(
            snapshot: snapshot, activeWorkoutID: nil,
            completedWorkoutIDs: [], slotAvailable: true
        ))
        XCTAssertFalse(ATHLTHStrengthWatchBootstrapAdmissionPolicy.canRestore(
            snapshot: snapshot, activeWorkoutID: UUID(),
            completedWorkoutIDs: [], slotAvailable: true
        ))
        XCTAssertFalse(ATHLTHStrengthWatchBootstrapAdmissionPolicy.canRestore(
            snapshot: snapshot, activeWorkoutID: nil,
            completedWorkoutIDs: [snapshot.workoutID], slotAvailable: true
        ))
        XCTAssertFalse(ATHLTHStrengthWatchBootstrapAdmissionPolicy.canRestore(
            snapshot: snapshot, activeWorkoutID: nil,
            completedWorkoutIDs: [], slotAvailable: false
        ))
        XCTAssertNotEqual(userID, snapshot.workoutID)
    }

    func testCompletedWatchCommandsAreAcknowledgedOnlyForCorrectAccount() {
        let owner = UUID()
        let other = UUID()
        let completedID = UUID()
        var command = WatchStrengthCommand(
            id: UUID(), workoutID: completedID, kind: .completeSet,
            reps: 10, weightKilograms: 30, restSeconds: 60,
            addRestSeconds: nil, sentAt: Date()
        )
        command.accountOwnerID = owner
        XCTAssertTrue(ATHLTHStrengthWatchCommandRoutingPolicy.mayAcknowledgeCommitted(
            command, signedInAccountID: owner,
            completedWorkoutIDs: [completedID]
        ))
        XCTAssertFalse(ATHLTHStrengthWatchCommandRoutingPolicy.mayAcknowledgeCommitted(
            command, signedInAccountID: other,
            completedWorkoutIDs: [completedID]
        ))
        XCTAssertFalse(ATHLTHStrengthWatchCommandRoutingPolicy.mayAcknowledgeCommitted(
            command, signedInAccountID: owner,
            completedWorkoutIDs: []
        ))
        // An old Watch build without an owner may be acknowledged only
        // when the exact immutable ID is already committed locally.
        command.accountOwnerID = nil
        XCTAssertTrue(ATHLTHStrengthWatchCommandRoutingPolicy.mayAcknowledgeCommitted(
            command, signedInAccountID: owner,
            completedWorkoutIDs: [completedID]
        ))
        command.workoutID = nil
        XCTAssertFalse(ATHLTHStrengthWatchCommandRoutingPolicy.mayAcknowledgeCommitted(
            command, signedInAccountID: owner,
            completedWorkoutIDs: [completedID]
        ))
    }

    func testWatchBootstrapIsProcessedBeforeOutOfOrderSetEvents() {
        let session = UUID()
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        func command(_ kind: WatchStrengthCommandKind, at offset: TimeInterval,
                     initiatedOnWatch: Bool? = nil) -> WatchStrengthCommand {
            WatchStrengthCommand(
                id: UUID(), workoutID: session, kind: kind,
                reps: nil, weightKilograms: nil, restSeconds: nil,
                addRestSeconds: nil, sentAt: start.addingTimeInterval(offset),
                initiatedOnWatch: initiatedOnWatch
            )
        }
        let set1 = command(.completeSet, at: 10)
        let set2 = command(.completeSet, at: 20)
        let bootstrap = command(.requestSnapshot, at: 25, initiatedOnWatch: true)
        let ordered = ATHLTHStrengthWatchCommandRoutingPolicy.orderedForReplay(
            [set2, set1, bootstrap]
        )
        XCTAssertEqual(ordered.map(\.id), [bootstrap.id, set1.id, set2.id])
    }

    func testSameAccountOfflineWatchCommandsWaitForMatchingWorkout() {
        let owner = UUID()
        let sessionA = UUID()
        let sessionB = UUID()
        var command = WatchStrengthCommand(
            id: UUID(), workoutID: sessionB, kind: .completeSet,
            reps: 10, weightKilograms: 40, restSeconds: 45,
            addRestSeconds: nil, sentAt: Date()
        )
        command.accountOwnerID = owner

        XCTAssertFalse(ATHLTHStrengthWatchCommandRoutingPolicy.mayProcess(
            command, signedInAccountID: owner,
            activeWorkoutID: sessionA
        ))
        XCTAssertFalse(ATHLTHStrengthWatchCommandRoutingPolicy.mayProcess(
            command, signedInAccountID: owner,
            activeWorkoutID: nil
        ))
        XCTAssertTrue(ATHLTHStrengthWatchCommandRoutingPolicy.mayProcess(
            command, signedInAccountID: owner,
            activeWorkoutID: sessionB
        ))

        // Watch-started bootstrap must survive another local session and
        // must still be allowed when no strength checkpoint is open.
        command.kind = .requestSnapshot
        command.initiatedOnWatch = true
        XCTAssertFalse(ATHLTHStrengthWatchCommandRoutingPolicy.mayProcess(
            command, signedInAccountID: owner,
            activeWorkoutID: sessionA
        ))
        XCTAssertTrue(ATHLTHStrengthWatchCommandRoutingPolicy.mayProcess(
            command, signedInAccountID: owner,
            activeWorkoutID: nil
        ))
        XCTAssertTrue(ATHLTHStrengthWatchCommandRoutingPolicy.mayProcess(
            command, signedInAccountID: owner,
            activeWorkoutID: sessionB
        ))

        // Read-only refresh from older Watch builds stays compatible.
        command.initiatedOnWatch = nil
        XCTAssertTrue(ATHLTHStrengthWatchCommandRoutingPolicy.mayProcess(
            command, signedInAccountID: owner,
            activeWorkoutID: sessionA
        ))
    }

    func testWatchOfflineJournalKeepsOtherAccountAndUnownedCommandsQueued() {
        let rightfulOwner = UUID()
        let otherOwner = UUID()
        let activeWorkoutID = UUID()
        var command = WatchStrengthCommand(
            id: UUID(), workoutID: activeWorkoutID, kind: .completeSet,
            reps: 8, weightKilograms: 24, restSeconds: 60,
            addRestSeconds: nil, sentAt: Date()
        )
        command.accountOwnerID = rightfulOwner
        XCTAssertTrue(ATHLTHStrengthWatchCommandRoutingPolicy.mayProcess(
            command,
            signedInAccountID: rightfulOwner,
            activeWorkoutID: activeWorkoutID
        ))
        XCTAssertFalse(ATHLTHStrengthWatchCommandRoutingPolicy.mayProcess(
            command,
            signedInAccountID: otherOwner,
            activeWorkoutID: activeWorkoutID
        ))
        command.accountOwnerID = nil
        XCTAssertTrue(ATHLTHStrengthWatchCommandRoutingPolicy.mayProcess(
            command,
            signedInAccountID: otherOwner,
            activeWorkoutID: activeWorkoutID
        ))
        XCTAssertFalse(ATHLTHStrengthWatchCommandRoutingPolicy.mayProcess(
            command,
            signedInAccountID: otherOwner,
            activeWorkoutID: UUID()
        ))
        command.kind = .requestSnapshot
        XCTAssertFalse(ATHLTHStrengthWatchCommandRoutingPolicy.mayProcess(
            command,
            signedInAccountID: rightfulOwner,
            activeWorkoutID: activeWorkoutID
        ))
    }


}
