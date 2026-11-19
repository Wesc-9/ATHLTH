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
        newer.id = UUID()
        newer.startedAt = first.startedAt.addingTimeInterval(120)
        newer.endedAt = first.startedAt.addingTimeInterval(180)
        try StrengthWorkoutCompletionJournal.save(newer, userID: owner)
        try StrengthWorkoutCompletionJournal.save(older, userID: owner)
        XCTAssertEqual(StrengthWorkoutCompletionJournal.read(userID: owner)?.id,
                       newer.id)
        XCTAssertEqual(StrengthWorkoutCompletionJournal.read(userID: owner)?.endedAt,
                       newer.endedAt)
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
}
