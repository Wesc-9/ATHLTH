import XCTest
@testable import ATHLTH

final class WorkoutIntegrity174Tests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func treadmill() -> PhoneWorkout {
        PhoneWorkout(walking: false, start: start, resumedAt: start,
                     lastCheckpoint: start, runEnvironment: .treadmill)
    }

    func testTreadmillIntegratesSpeedChangesAndExcludesPause() {
        var workout = treadmill()
        workout.setTreadmillSpeed(10, at: start)
        workout.advanceTreadmillDistance(at: start.addingTimeInterval(720))
        XCTAssertEqual(workout.distanceMeters, 2_000, accuracy: 0.001)
        workout.accumulatedSeconds = 720
        workout.resumedAt = nil
        workout.advanceTreadmillDistance(at: start.addingTimeInterval(1_020))
        XCTAssertEqual(workout.distanceMeters, 2_000, accuracy: 0.001)
        workout.setTreadmillSpeed(12, at: start.addingTimeInterval(1_020))
        workout.resumedAt = start.addingTimeInterval(1_020)
        workout.advanceTreadmillDistance(at: start.addingTimeInterval(1_320))
        XCTAssertEqual(workout.distanceMeters, 3_000, accuracy: 0.001)
        XCTAssertEqual(workout.elapsed(at: start.addingTimeInterval(1_320)), 1_020)
        // Duplicate ticks cannot double count the same active time.
        workout.advanceTreadmillDistance(at: start.addingTimeInterval(1_320))
        XCTAssertEqual(workout.distanceMeters, 3_000, accuracy: 0.001)
    }

    func testEnteringSpeedDoesNotBackfillUnknownDistanceOrAffectOutdoorRun() {
        var workout = treadmill()
        workout.advanceTreadmillDistance(at: start.addingTimeInterval(300))
        workout.setTreadmillSpeed(12, at: start.addingTimeInterval(300))
        workout.advanceTreadmillDistance(at: start.addingTimeInterval(600))
        XCTAssertEqual(workout.distanceMeters, 1_000, accuracy: 0.001)
        workout.setTreadmillSpeed(.nan, at: start.addingTimeInterval(600))
        XCTAssertEqual(workout.treadmillSpeedKilometersPerHour, 12)
        workout.runEnvironment = .outdoor
        workout.advanceTreadmillDistance(at: start.addingTimeInterval(900))
        XCTAssertEqual(workout.distanceMeters, 1_000, accuracy: 0.001)
    }

    func testPersistedTreadmillAnchorContinuesWithoutDoubleCounting() throws {
        var workout = treadmill()
        workout.setTreadmillSpeed(10, at: start)
        workout.advanceTreadmillDistance(at: start.addingTimeInterval(360))
        var restored = try JSONDecoder().decode(PhoneWorkout.self, from: JSONEncoder().encode(workout))
        restored.advanceTreadmillDistance(at: start.addingTimeInterval(720))
        XCTAssertEqual(restored.distanceMeters, 2_000, accuracy: 0.001)
    }

    func testCompletedWatchDurationDoesNotGrowWithLateDeliveryOrPause() {
        let snapshot = WatchWorkoutLiveSnapshot(
            kind: .strength, state: .completed, startedAt: start,
            capturedAt: start.addingTimeInterval(1_800), elapsedTime: 1_200,
            heartRate: 0, activeCalories: 50, distanceMeters: 0,
            averageHeartRate: nil, maxHeartRate: nil, routePointCount: 0
        )
        XCTAssertEqual(snapshot.confirmedActiveDuration, 1_200)
        var invalid = snapshot
        invalid.elapsedTime = .nan
        XCTAssertEqual(invalid.confirmedActiveDuration, 0)
    }

    @MainActor
    func testJournalRecoversCompletionBeforeHistoryFlushAndClearsOldActiveOnce() throws {
        let owner = UUID(), other = UUID()
        defer {
            PhoneWorkoutCompletionJournal.remove(userID: owner)
            for name in ["phoneActive", "phoneHistory"] {
                UserDefaults.standard.removeObject(forKey: AccountLocalStorage.key(name, userID: owner))
            }
        }
        var workout = treadmill()
        AccountLocalStorage.write(workout, name: "phoneActive", userID: owner)
        workout.end = start.addingTimeInterval(600)
        workout.accumulatedSeconds = 600
        workout.resumedAt = nil
        try PhoneWorkoutCompletionJournal.save(workout, userID: owner)
        XCTAssertNil(PhoneWorkoutCompletionJournal.read(userID: other))
        let store = IPhoneWorkoutStore()
        store.switchAccount(owner)
        XCTAssertNil(store.active)
        XCTAssertEqual(store.history.map(\.id), [workout.id])
        let reopened = IPhoneWorkoutStore()
        reopened.switchAccount(owner)
        XCTAssertNil(reopened.active)
        XCTAssertEqual(reopened.history.map(\.id), [workout.id])
        reopened.removeWorkoutFromHistory(matching: [workout.id])
        XCTAssertNil(PhoneWorkoutCompletionJournal.read(userID: owner))
        let afterDeletion = IPhoneWorkoutStore()
        afterDeletion.switchAccount(owner)
        // A durable completion must not reappear after its history entry is removed.
        XCTAssertTrue(afterDeletion.history.isEmpty)
        XCTAssertNil(afterDeletion.active)
    }

    func testFailedEncodingDoesNotReplacePreviousDurableCompletion() throws {
        let owner = UUID()
        defer { PhoneWorkoutCompletionJournal.remove(userID: owner) }
        var completed = treadmill()
        completed.end = start.addingTimeInterval(60)
        try PhoneWorkoutCompletionJournal.save(completed, userID: owner)
        var invalid = completed
        invalid.id = UUID()
        invalid.distanceMeters = .nan
        XCTAssertThrowsError(try PhoneWorkoutCompletionJournal.save(invalid, userID: owner))
        XCTAssertEqual(PhoneWorkoutCompletionJournal.read(userID: owner)?.id, completed.id)
    }

    @MainActor
    func testCompletionSummariesAreIsolatedAcrossAccountsLogoutAndDeletion() {
        let suite = "workout-completion-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID(), second = UUID(), workoutID = UUID()
        let impact = WorkoutCompletionImpact(workoutID: workoutID, generatedAt: Date(), items: [])
        AccountLocalStorage.write([impact], name: "workoutCompletionImpacts", userID: first, defaults: defaults)
        let store = WorkoutCompletionCoordinator(defaults: defaults)
        XCTAssertTrue(store.impacts.isEmpty)
        store.switchAccount(first)
        XCTAssertNotNil(store.impact(for: workoutID))
        store.switchAccount(second)
        XCTAssertTrue(store.impacts.isEmpty)
        store.switchAccount(nil)
        XCTAssertTrue(store.impacts.isEmpty)
        store.switchAccount(first)
        XCTAssertNotNil(store.impact(for: workoutID))
        store.switchAccount(nil)
        defaults.set(true, forKey: AccountLocalStorage.key("deleted", userID: first))
        store.switchAccount(first)
        XCTAssertTrue(store.impacts.isEmpty)
    }
}
