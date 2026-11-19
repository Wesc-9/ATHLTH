import Foundation
import XCTest
@testable import ATHLTH

final class StrengthWorkoutCompletionRecoveryTests: XCTestCase {
    @MainActor
    func testDelayedWatchResultCannotEndOrModifyAnotherStrengthSession() throws {
        let owner = UUID()
        defer {
            StrengthWorkoutCompletionJournal.remove(userID: owner)
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthHistory", userID: owner)
            )
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthActive", userID: owner)
            )
        }

        let store = StrengthWorkoutStore()
        store.switchAccount(owner)
        store.startFreestyle(watchSessionID: UUID(), captureDevice: .appleWatch)
        let original = try XCTUnwrap(store.activeWorkout)
        var result = WatchWorkoutResult(
            id: UUID(), kind: .strength, healthKitWorkoutUUID: UUID(),
            startedAt: original.startedAt,
            endedAt: original.startedAt.addingTimeInterval(120),
            duration: 120, activeCalories: 60, distanceMeters: 0,
            averageHeartRate: 120, maxHeartRate: 145, routePointCount: 0
        )
        result.strengthSnapshot = try XCTUnwrap(store.watchSnapshot)

        XCTAssertTrue(ATHLTHWatchStrengthResultIdentityPolicy.matches(
            result: result, workout: original
        ))
        var mismatchedResult = result
        var wrongSnapshot = try XCTUnwrap(result.strengthSnapshot)
        wrongSnapshot.workoutID = UUID()
        mismatchedResult.strengthSnapshot = wrongSnapshot
        XCTAssertFalse(ATHLTHWatchStrengthResultIdentityPolicy.matches(
            result: mismatchedResult, workout: original
        ))
        var wrongCapture = original
        wrongCapture.captureDevice = .iPhone
        XCTAssertFalse(ATHLTHWatchStrengthResultIdentityPolicy.matches(
            result: result, workout: wrongCapture
        ))
        // The result ID itself is unrelated to the authoritative workout.
        XCTAssertNotEqual(result.id, original.id)
        XCTAssertTrue(store.finish(completedAt: result.endedAt))
        XCTAssertEqual(store.workoutHistory.first?.endedAt, result.endedAt)

        // A different current session must survive late metrics from the
        // previous finished workout; only its exact history entry changes.
        let originalID = original.id
        store.startFreestyle(watchSessionID: UUID(), captureDevice: .appleWatch)
        let nextID = try XCTUnwrap(store.activeWorkout?.id)
        let measured = LinkedHealthWorkoutMetrics(
            healthKitWorkoutUUID: result.healthKitWorkoutUUID,
            duration: 120, activeCalories: 60,
            averageHeartRate: 120, maxHeartRate: 145
        )
        XCTAssertTrue(store.attachFinishedWatchMetrics(
            measured, workoutID: originalID, ownerID: owner
        ))
        XCTAssertEqual(store.activeWorkout?.id, nextID)
        XCTAssertNil(store.activeWorkout?.healthMetrics.healthKitWorkoutUUID)
        XCTAssertEqual(
            store.workoutHistory.first(where: { $0.id == originalID })?
                .healthMetrics.healthKitWorkoutUUID,
            result.healthKitWorkoutUUID
        )
        XCTAssertFalse(store.attachFinishedWatchMetrics(
            measured, workoutID: nextID, ownerID: owner
        ))
        // A later callback without HealthKit identity must not clear the
        // already linked UUID from a completed Watch workout.
        let missingIdentity = LinkedHealthWorkoutMetrics(
            healthKitWorkoutUUID: nil,
            duration: 125, activeCalories: 63,
            averageHeartRate: 121, maxHeartRate: 146
        )
        XCTAssertFalse(store.attachFinishedWatchMetrics(
            missingIdentity, workoutID: originalID, ownerID: owner
        ))
        XCTAssertEqual(
            store.workoutHistory.first(where: { $0.id == originalID })?
                .healthMetrics.healthKitWorkoutUUID,
            result.healthKitWorkoutUUID
        )
        // Reusing this HealthKit recording for a second completed session
        // would double-count the original Apple Health workout.
        XCTAssertTrue(store.finish())
        XCTAssertFalse(store.attachFinishedWatchMetrics(
            measured, workoutID: nextID, ownerID: owner
        ))
    }

    @MainActor
    func testWatchResultImportWaitsForCorrectStrengthSessionWithoutBlockingOtherSports() throws {
        let owner = UUID()
        defer {
            StrengthWorkoutCompletionJournal.remove(userID: owner)
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthHistory", userID: owner)
            )
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthActive", userID: owner)
            )
        }

        let store = StrengthWorkoutStore()
        store.switchAccount(owner)
        store.startFreestyle(watchSessionID: UUID(), captureDevice: .appleWatch)
        let active = try XCTUnwrap(store.activeWorkout)
        var result = WatchWorkoutResult(
            id: UUID(), kind: .strength, healthKitWorkoutUUID: UUID(),
            startedAt: active.startedAt,
            endedAt: active.startedAt.addingTimeInterval(60),
            duration: 60, activeCalories: 30, distanceMeters: 0,
            averageHeartRate: 115, maxHeartRate: 140, routePointCount: 0
        )
        result.strengthSnapshot = try XCTUnwrap(store.watchSnapshot)

        func eligible(_ result: WatchWorkoutResult,
                      activeStrength: StrengthWorkoutLog?,
                      savedStrength: [StrengthWorkoutLog] = [],
                      ready: Bool = true,
                      free: Bool = false) -> Bool {
            ATHLTHWatchStrengthResultIdentityPolicy.canReconcile(
                result: result, activeStrength: activeStrength,
                savedStrength: savedStrength, strengthAccountReady: ready,
                recordingSlotAvailable: free
            )
        }

        XCTAssertTrue(eligible(result, activeStrength: active))
        XCTAssertFalse(eligible(result, activeStrength: active, ready: false))
        var otherResult = result
        var otherSnapshot = try XCTUnwrap(result.strengthSnapshot)
        otherSnapshot.workoutID = UUID()
        otherResult.strengthSnapshot = otherSnapshot
        XCTAssertFalse(eligible(otherResult, activeStrength: active))
        XCTAssertFalse(eligible(otherResult, activeStrength: nil))
        XCTAssertTrue(eligible(otherResult, activeStrength: nil, free: true))

        // A previously completed exact match remains importable while a
        // different strength session is recording. No duplicate recording.
        XCTAssertTrue(store.finish())
        let finished = try XCTUnwrap(store.workoutHistory.first)
        store.startFreestyle(watchSessionID: UUID(), captureDevice: .appleWatch)
        let newer = try XCTUnwrap(store.activeWorkout)
        XCTAssertTrue(eligible(result, activeStrength: newer, savedStrength: [finished]))
        XCTAssertFalse(eligible(otherResult, activeStrength: newer, savedStrength: [finished]))

        result.kind = .running
        XCTAssertTrue(eligible(result, activeStrength: newer),
                      "Unrelated sport must not be blocked behind a strength result")
        result.kind = .strength
        result.strengthSnapshot = nil
        XCTAssertTrue(eligible(result, activeStrength: newer),
                      "Legacy Watch results keep their generic processing route")
    }

    @MainActor
    func testLatePhoneHealthKitUUIDBackfillsExactWorkoutWithoutRewindingJournal() throws {
        let owner = UUID()
        defer {
            StrengthWorkoutCompletionJournal.remove(userID: owner)
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthHistory", userID: owner)
            )
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthActive", userID: owner)
            )
        }

        let store = StrengthWorkoutStore()
        store.switchAccount(owner)
        store.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        let firstID = try XCTUnwrap(store.activeWorkout?.id)
        XCTAssertTrue(store.finish())
        store.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        let secondID = try XCTUnwrap(store.activeWorkout?.id)
        XCTAssertTrue(store.finish())
        XCTAssertEqual(StrengthWorkoutCompletionJournal.read(userID: owner)?.id, secondID)

        let uuid = UUID()
        XCTAssertTrue(store.attachFinishedWorkoutHealthKitUUID(
            uuid, workoutID: firstID, ownerID: owner
        ))
        XCTAssertTrue(store.attachFinishedWorkoutHealthKitUUID(
            uuid, workoutID: firstID, ownerID: owner
        ), "Duplicate callback for the same HealthKit UUID is harmless")
        XCTAssertFalse(store.attachFinishedWorkoutHealthKitUUID(
            UUID(), workoutID: firstID, ownerID: owner
        ), "A second HealthKit recording cannot steal a committed session")
        XCTAssertFalse(store.attachFinishedWorkoutHealthKitUUID(
            UUID(), workoutID: secondID, ownerID: UUID()
        ), "Never attach a previous account's HealthKit UUID")
        XCTAssertFalse(store.attachFinishedWorkoutHealthKitUUID(
            UUID(), workoutID: UUID(), ownerID: owner
        ))
        XCTAssertFalse(store.attachFinishedWorkoutHealthKitUUID(
            uuid, workoutID: secondID, ownerID: owner
        ), "One HealthKit workout UUID cannot identify two finished sessions")

        XCTAssertEqual(
            store.workoutHistory.first(where: { $0.id == firstID })?
                .healthMetrics.healthKitWorkoutUUID,
            uuid
        )
        XCTAssertNil(
            store.workoutHistory.first(where: { $0.id == secondID })?
                .healthMetrics.healthKitWorkoutUUID
        )
        XCTAssertEqual(
            StrengthWorkoutCompletionJournal.read(userID: owner)?.id,
            secondID,
            "Late HealthKit writes must not overwrite the newest completion"
        )
    }

    @MainActor
    func testFinishedStrengthWorkoutIsRestoredAfterHistoryWriteIsLost() throws {
        let userID = UUID()
        defer {
            StrengthWorkoutCompletionJournal.remove(userID: userID)
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthHistory", userID: userID)
            )
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthActive", userID: userID)
            )
        }

        let store = StrengthWorkoutStore()
        store.switchAccount(userID)
        let plan = PlannedSession(
            id: UUID(), title: "Recovery test", kind: .strength,
            scheduledStart: nil, durationMinutes: 20,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: nil
        )
        store.start(
            session: plan, watchSessionID: nil,
            trackingMode: .advanced, captureDevice: .iPhone
        )
        let activeID = try XCTUnwrap(store.activeWorkout?.id)
        XCTAssertThrowsError(
            try StrengthWorkoutCompletionJournal.save(
                try XCTUnwrap(store.activeWorkout), userID: userID
            )
        )

        XCTAssertTrue(store.finish())
        XCTAssertNil(store.activeWorkout)
        XCTAssertNil(store.completionSaveError)
        XCTAssertEqual(store.workoutHistory.filter { $0.id == activeID }.count, 1)
        XCTAssertEqual(StrengthWorkoutCompletionJournal.read(userID: userID)?.id, activeID)
        let finished = try XCTUnwrap(store.workoutHistory.first { $0.id == activeID })
        let ended = try XCTUnwrap(finished.endedAt)
        XCTAssertGreaterThanOrEqual(ended, finished.startedAt)
        XCTAssertLessThanOrEqual(abs(ended.timeIntervalSinceNow), 5)

        // Simulate UserDefaults history not surviving a process exit while
        // the atomic journal did. The active checkpoint may still exist.
        try AccountLocalStorage.writeChecked(
            [StrengthWorkoutLog](), name: "strengthHistory", userID: userID
        )
        let restored = StrengthWorkoutStore()
        restored.switchAccount(userID)
        XCTAssertNil(restored.activeWorkout)
        XCTAssertEqual(restored.workoutHistory.filter { $0.id == activeID }.count, 1)

        // Repeated launches must not generate duplicate sessions.
        let secondRead = StrengthWorkoutStore()
        secondRead.switchAccount(userID)
        XCTAssertEqual(secondRead.workoutHistory.filter { $0.id == activeID }.count, 1)

        secondRead.removeWorkoutFromHistory(matching: [activeID])
        XCTAssertNil(StrengthWorkoutCompletionJournal.read(userID: userID))
    }

    @MainActor
    func testStrengthCompletionJournalRejectsInvalidFinishAndOlderReceipt() throws {
        let owner = UUID()
        defer {
            StrengthWorkoutCompletionJournal.remove(userID: owner)
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthHistory", userID: owner)
            )
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthActive", userID: owner)
            )
        }

        let store = StrengthWorkoutStore()
        store.switchAccount(owner)
        store.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        let first = try XCTUnwrap(store.activeWorkout)
        var invalid = first
        invalid.endedAt = first.startedAt.addingTimeInterval(-1)
        XCTAssertThrowsError(
            try StrengthWorkoutCompletionJournal.save(invalid, userID: owner)
        )
        XCTAssertNil(StrengthWorkoutCompletionJournal.read(userID: owner))

        var older = first
        older.endedAt = first.startedAt.addingTimeInterval(60)
        var newer = first
        newer.endedAt = first.startedAt.addingTimeInterval(180)
        try StrengthWorkoutCompletionJournal.save(newer, userID: owner)
        try StrengthWorkoutCompletionJournal.save(older, userID: owner)
        XCTAssertEqual(StrengthWorkoutCompletionJournal.read(userID: owner)?.id,
                       newer.id)
        XCTAssertEqual(StrengthWorkoutCompletionJournal.read(userID: owner)?.endedAt,
                       newer.endedAt)

        // Two distinct workouts can share the same end timestamp.
        // A late packet must not replace the already durable identity.
        let otherStore = StrengthWorkoutStore()
        let otherOwner = UUID()
        defer {
            StrengthWorkoutCompletionJournal.remove(userID: otherOwner)
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthHistory", userID: otherOwner)
            )
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthActive", userID: otherOwner)
            )
        }
        otherStore.switchAccount(otherOwner)
        otherStore.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        var other = try XCTUnwrap(otherStore.activeWorkout)
        other.endedAt = newer.endedAt
        XCTAssertNotEqual(other.id, newer.id)
        try StrengthWorkoutCompletionJournal.save(other, userID: owner)
        XCTAssertEqual(StrengthWorkoutCompletionJournal.read(userID: owner)?.id,
                       newer.id)
    }

    @MainActor
    func testStrengthCompletionJournalIsIsolatedBetweenAccounts() throws {
        let firstAccount = UUID()
        let secondAccount = UUID()
        defer {
            for account in [firstAccount, secondAccount] {
                StrengthWorkoutCompletionJournal.remove(userID: account)
                UserDefaults.standard.removeObject(
                    forKey: AccountLocalStorage.key("strengthHistory", userID: account)
                )
                UserDefaults.standard.removeObject(
                    forKey: AccountLocalStorage.key("strengthActive", userID: account)
                )
            }
        }

        let store = StrengthWorkoutStore()
        store.switchAccount(firstAccount)
        store.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        var completed = try XCTUnwrap(store.activeWorkout)
        completed.endedAt = completed.startedAt.addingTimeInterval(30)
        try StrengthWorkoutCompletionJournal.save(completed, userID: firstAccount)
        XCTAssertNil(StrengthWorkoutCompletionJournal.read(userID: secondAccount))
        XCTAssertEqual(StrengthWorkoutCompletionJournal.read(userID: firstAccount)?.id,
                       completed.id)
    }

    @MainActor
    func testAccountHistoryMergeDoesNotDuplicateHealthKitRecording() throws {
        let localOwner = UUID()
        let remoteOwner = UUID()
        defer {
            for owner in [localOwner, remoteOwner] {
                StrengthWorkoutCompletionJournal.remove(userID: owner)
                UserDefaults.standard.removeObject(
                    forKey: AccountLocalStorage.key("strengthHistory", userID: owner)
                )
                UserDefaults.standard.removeObject(
                    forKey: AccountLocalStorage.key("strengthActive", userID: owner)
                )
            }
        }

        let sharedHealthKitUUID = UUID()
        let local = StrengthWorkoutStore()
        local.switchAccount(localOwner)
        local.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        XCTAssertTrue(local.finish(healthKitWorkoutUUID: sharedHealthKitUUID))
        let saved = try XCTUnwrap(local.workoutHistory.first)

        let remote = StrengthWorkoutStore()
        remote.switchAccount(remoteOwner)
        remote.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        XCTAssertTrue(remote.finish(healthKitWorkoutUUID: sharedHealthKitUUID))
        let duplicate = try XCTUnwrap(remote.workoutHistory.first)
        XCTAssertNotEqual(saved.id, duplicate.id)

        XCTAssertEqual(
            try local.mergeAccountSyncedWorkouts([duplicate], for: localOwner), 0
        )
        XCTAssertEqual(local.workoutHistory.count, 1)
        XCTAssertEqual(local.workoutHistory.first?.id, saved.id)
        XCTAssertEqual(
            local.workoutHistory.first?.healthMetrics.healthKitWorkoutUUID,
            sharedHealthKitUUID
        )

        var invalidInterval = duplicate
        invalidInterval.endedAt = invalidInterval.startedAt.addingTimeInterval(-1)
        XCTAssertEqual(
            try local.mergeAccountSyncedWorkouts([invalidInterval], for: localOwner), 0
        )
        XCTAssertEqual(local.workoutHistory.count, 1)
    }

    @MainActor
    func testResultBreakdownExcludesUncompletedSetsAndClampsRest() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        let exercise = Exercise(
            id: UUID(), origin: .publicCatalog, ownerID: nil,
            name: "Phase 7 squat", instructions: [],
            primaryMuscles: ["Quadriceps"], secondaryMuscles: [],
            equipment: [], imageURL: nil, isVisibleOutsideOwnerLibrary: true
        )
        store.appendExercise(exercise, sets: 2, reps: 10, restSeconds: 60)
        var workout = try XCTUnwrap(store.activeWorkout)
        XCTAssertEqual(workout.exercises.count, 1)
        XCTAssertEqual(workout.exercises[0].sets.count, 2)
        workout.exercises[0].sets[0].completedAt =
            workout.startedAt.addingTimeInterval(20)
        workout.exercises[0].sets[0].completedReps = 10
        workout.exercises[0].sets[0].completedWeightKilograms = 20
        workout.exercises[0].sets[0].actualSetElapsedSeconds = 20
        workout.exercises[0].sets[0].actualRestAfterSeconds = 40
        // Legacy draft values on a skipped set are not completed evidence.
        workout.exercises[0].sets[1].completedReps = 50
        workout.exercises[0].sets[1].skippedAt =
            workout.startedAt.addingTimeInterval(70)
        workout.exercises[0].sets[1].actualRestAfterSeconds = 800

        XCTAssertEqual(workout.totalCompletedReps, 10)
        XCTAssertEqual(workout.recordedRestDurationsSeconds, [40])
        XCTAssertEqual(workout.totalActualRestSeconds, 40)
        let summary = StrengthWorkoutResultBreakdown(
            workout: workout, elapsedSeconds: 180
        )
        XCTAssertEqual(summary.totalSeconds, 180)
        XCTAssertEqual(summary.restSeconds, 40)
        XCTAssertEqual(summary.activeSeconds, 140)
        XCTAssertEqual(summary.segments[0].completedSets, 1)
        XCTAssertEqual(summary.segments[0].completedReps, 10)
        XCTAssertEqual(summary.segments[0].registeredEffortSeconds, 20)

        // Imported HealthKit time is used only when valid. Rest can
        // never exceed total recorded duration in the final summary.
        workout.healthMetrics.duration = 90
        workout.exercises[0].sets[0].actualRestAfterSeconds = 200
        let bounded = StrengthWorkoutResultBreakdown(
            workout: workout, elapsedSeconds: 180
        )
        XCTAssertEqual(bounded.totalSeconds, 90)
        XCTAssertEqual(bounded.restSeconds, 90)
        XCTAssertEqual(bounded.activeSeconds, 0)
        workout.healthMetrics.duration = .infinity
        XCTAssertEqual(
            StrengthWorkoutResultBreakdown(
                workout: workout, elapsedSeconds: 180
            ).totalSeconds, 180
        )
    }

    @MainActor
    func testHybridResultKeepsSensorDistanceSeparateFromManualEstimates() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
        let exercise = Exercise(
            id: UUID(), origin: .publicCatalog, ownerID: nil,
            name: "Phase 7 interval", instructions: [],
            primaryMuscles: [], secondaryMuscles: [],
            equipment: [], imageURL: nil, isVisibleOutsideOwnerLibrary: true
        )
        store.appendExercise(
            exercise, sets: 1, reps: nil, targetKind: .time,
            targetDurationSeconds: 60, restSeconds: 0
        )
        var workout = try XCTUnwrap(store.activeWorkout)
        workout.exercises[0].isEmbeddedRunningInterval = true
        workout.exercises[0].sets[0].completedAt =
            workout.startedAt.addingTimeInterval(70)
        workout.exercises[0].sets[0].completedDurationSeconds = 60
        workout.exercises[0].sets[0].actualSetElapsedSeconds = 70
        workout.exercises[0].sets[0].watchActiveDurationSeconds = 65
        workout.exercises[0].sets[0].watchMeasuredDistanceMeters = 220
        workout.exercises[0].sets[0].completedDistanceMeters = 220
        workout.exercises[0].sets[0].manuallyEstimatedTreadmillDistanceMeters = 250

        let segment = try XCTUnwrap(
            StrengthWorkoutResultBreakdown(
                workout: workout, elapsedSeconds: 90
            ).segments.first
        )
        XCTAssertTrue(segment.isCardio)
        XCTAssertEqual(segment.completedSets, 1)
        XCTAssertEqual(segment.registeredEffortSeconds, 70)
        XCTAssertEqual(segment.measuredDistanceMeters, 220)
        XCTAssertEqual(segment.loggedDistanceMeters, 0)
        XCTAssertEqual(segment.estimatedTreadmillDistanceMeters, 250)
    }

    @MainActor
    func testHistoricalStrengthPRUsesOnlyEarlierCompletedWorkouts() throws {
        let owner = UUID()
        defer {
            StrengthWorkoutCompletionJournal.remove(userID: owner)
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthHistory", userID: owner)
            )
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key("strengthActive", userID: owner)
            )
        }
        let store = StrengthWorkoutStore()
        store.switchAccount(owner)
        let exercise = Exercise(
            id: UUID(), origin: .publicCatalog, ownerID: nil,
            name: "Phase 7 bench press", instructions: [],
            primaryMuscles: ["Chest"], secondaryMuscles: [],
            equipment: [], imageURL: nil, isVisibleOutsideOwnerLibrary: true
        )

        for weight in [90.0, 80.0, 100.0] {
            store.startFreestyle(watchSessionID: nil, captureDevice: .iPhone)
            store.appendExercise(exercise, sets: 1, reps: 3, restSeconds: 0)
            store.setDraft(reps: 3, weightKilograms: weight)
            store.completeCurrentDraftSet()
            XCTAssertTrue(store.finish())
        }

        let chronological = store.workoutHistory.sorted {
            $0.startedAt < $1.startedAt
        }
        XCTAssertEqual(chronological.count, 3)
        XCTAssertTrue(
            store.workoutPersonalRecords(for: chronological[0]).isEmpty,
            "The first workout remains a baseline, even after later training"
        )
        XCTAssertTrue(
            store.workoutPersonalRecords(for: chronological[1]).isEmpty,
            "Lighter training is not a new PR"
        )
        XCTAssertFalse(
            store.workoutPersonalRecords(for: chronological[2]).isEmpty,
            "The genuine later improvement is supported by prior evidence"
        )
    }
}
