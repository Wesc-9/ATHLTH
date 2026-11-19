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
        var other = original
        other.id = UUID()
        XCTAssertFalse(ATHLTHWatchStrengthResultIdentityPolicy.matches(
            result: result, workout: other
        ))
        other = original
        other.captureDevice = .iPhone
        XCTAssertFalse(ATHLTHWatchStrengthResultIdentityPolicy.matches(
            result: result, workout: other
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
}
