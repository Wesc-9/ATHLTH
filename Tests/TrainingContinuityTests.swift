import XCTest
import CoreLocation
@testable import ATHLTH

final class TrainingContinuityTests: XCTestCase {
    @MainActor
    func testGoalsRemainPrivateAcrossAccountSwitchAndRelaunch() {
        let first = UUID(), second = UUID()
        defer { clear(first); clear(second) }
        let store = GoalStore()
        store.switchAccount(first)
        let goal = ATHLTHGoal(title: "Private goal", category: .consistency, dataSource: .manual)
        store.add(goal)
        store.switchAccount(second)
        XCTAssertTrue(store.goals.isEmpty)
        store.switchAccount(nil)
        XCTAssertTrue(store.goals.isEmpty)
        let reopened = GoalStore()
        reopened.switchAccount(first)
        XCTAssertEqual(reopened.goals.map(\.id), [goal.id])
    }

    @MainActor
    func testStrengthSetsRecoverWithoutLeakingOrDuplicatingCompletedWorkout() {
        let first = UUID(), second = UUID()
        defer { clear(first); clear(second) }
        let store = StrengthWorkoutStore()
        store.switchAccount(first)
        store.startFreestyle(watchSessionID: nil)
        let exercise = Exercise(id: UUID(), origin: .custom, ownerID: first, name: "Squat", instructions: [], primaryMuscles: [], secondaryMuscles: [], equipment: [], imageURL: nil, isVisibleOutsideOwnerLibrary: false)
        store.appendExercise(exercise, sets: 3)
        store.completeCurrentSet(reps: 8, weightKilograms: 50, rpe: 7)
        let id = store.activeWorkout?.id
        store.switchAccount(second)
        XCTAssertNil(store.activeWorkout)
        XCTAssertTrue(store.workoutHistory.isEmpty)
        let reopened = StrengthWorkoutStore()
        reopened.switchAccount(first)
        XCTAssertEqual(reopened.activeWorkout?.id, id)
        XCTAssertEqual(reopened.activeWorkout?.exercises.first?.sets.first?.completedWeightKilograms, 50)
        reopened.finish()
        let finished = StrengthWorkoutStore()
        finished.switchAccount(first)
        XCTAssertNil(finished.activeWorkout)
        XCTAssertEqual(finished.workoutHistory.count, 1)
        XCTAssertEqual(finished.workoutHistory.first?.id, id)
    }

    func testBackupRejectsWrongOwnerUnknownVersionAndMalformedData() throws {
        let owner = UUID()
        let valid = TrainingBackupPayload(version: 1, ownerID: owner, records: ["goals": Data("[]".utf8)])
        XCTAssertNoThrow(try valid.validate(for: owner))
        XCTAssertThrowsError(try valid.validate(for: UUID()))
        XCTAssertThrowsError(try TrainingBackupPayload(version: 2, ownerID: owner, records: [:]).validate(for: owner))
        XCTAssertThrowsError(try TrainingBackupPayload(version: 1, ownerID: owner, records: ["goals": Data("{}".utf8)]).validate(for: owner))
        XCTAssertThrowsError(try TrainingBackupPayload(version: 1, ownerID: owner, records: ["coachHistoryConsent": Data("true".utf8)]).validate(for: owner))
    }

    func testPhoneWorkoutTimerExcludesPausedTime() {
        let start = Date(timeIntervalSince1970: 1000)
        var workout = PhoneWorkout(walking: false, start: start, accumulatedSeconds: 120, resumedAt: start, lastCheckpoint: start)
        XCTAssertEqual(workout.elapsed(at: start.addingTimeInterval(30)), 150)
        workout.resumedAt = nil
        XCTAssertEqual(workout.elapsed(at: start.addingTimeInterval(3600)), 120)
    }

    @MainActor
    func testPhoneRecoveryStopsAtCheckpointAndIsAccountScoped() {
        let first = UUID(), second = UUID()
        defer { clear(first); clear(second) }
        let start = Date().addingTimeInterval(-3600)
        let saved = PhoneWorkout(walking: true, start: start, resumedAt: start, lastCheckpoint: start.addingTimeInterval(120))
        AccountLocalStorage.write(saved, name: "phoneActive", userID: first)
        let store = IPhoneWorkoutStore()
        store.switchAccount(first)
        XCTAssertNil(store.active?.resumedAt)
        XCTAssertEqual(store.active?.accumulatedSeconds, 120)
        store.switchAccount(second)
        XCTAssertNil(store.active)
        XCTAssertTrue(store.history.isEmpty)
    }

    @MainActor
    func testCloudBackupRequiresSeparateOptInForEachAccount() {
        let first = UUID(), second = UUID()
        defer {
            for id in [first, second] {
                for name in ["cloudBackupConsent", "cloudBackupConsentChangedAt"] {
                    UserDefaults.standard.removeObject(forKey: AccountLocalStorage.key(name, userID: id))
                }
            }
        }
        let store = TrainingBackupStore()
        store.switchAccount(first)
        XCTAssertFalse(store.enabled)
        AccountLocalStorage.write(true, name: "cloudBackupConsent", userID: first)
        store.switchAccount(second)
        XCTAssertFalse(store.enabled)
        store.switchAccount(first)
        XCTAssertTrue(store.enabled)
        AccountLocalStorage.write(false, name: "cloudBackupConsent", userID: first)
        store.switchAccount(first)
        XCTAssertFalse(store.enabled)
    }

    @MainActor
    func testCloudSnapshotOmitsImportedHealthReadings() throws {
        let owner = UUID()
        defer { clear(owner) }
        let store = StrengthWorkoutStore()
        store.switchAccount(owner)
        store.startFreestyle(watchSessionID: nil)
        store.finish(duration: 300, activeCalories: 100, averageHeartRate: 140, maxHeartRate: 170)
        let payload = try TrainingBackupPayload.capture(userID: owner)
        let logs = try JSONDecoder().decode([StrengthWorkoutLog].self, from: XCTUnwrap(payload.records["strengthHistory"]))
        XCTAssertNil(logs.first?.healthMetrics.averageHeartRate)
        XCTAssertNil(logs.first?.healthMetrics.activeCalories)
        XCTAssertEqual(store.workoutHistory.first?.healthMetrics.averageHeartRate, 140)
    }

    func testCorruptHistoryCannotBypassBackupFiltering() {
        let owner = UUID()
        defer { clear(owner) }
        UserDefaults.standard.set(Data("{\"averageHeartRate\":140}".utf8), forKey: AccountLocalStorage.key("strengthHistory", userID: owner))
        XCTAssertThrowsError(try TrainingBackupPayload.capture(userID: owner))
    }

    func testBackupStripsRecordedGPSAndProducesStableSnapshots() throws {
        let owner = UUID()
        defer { clear(owner) }
        let start = Date()
        var workout = PhoneWorkout(walking: true, start: start, lastCheckpoint: start)
        workout.points = [PhoneRoutePoint(CLLocation(latitude: 63.4, longitude: 10.4))]
        AccountLocalStorage.write([workout], name: "phoneHistory", userID: owner)
        let first = try TrainingBackupPayload.capture(userID: owner)
        XCTAssertEqual(first, try TrainingBackupPayload.capture(userID: owner))
        let restored = try JSONDecoder().decode([PhoneWorkout].self, from: XCTUnwrap(first.records["phoneHistory"]))
        XCTAssertTrue(try XCTUnwrap(restored.first).points.isEmpty)
        XCTAssertEqual(AccountLocalStorage.read([PhoneWorkout].self, name: "phoneHistory", userID: owner)?.first?.points.count, 1)
    }

    func testCloudPermissionDoesNotAuthorizeCoachHistory() {
        let owner = UUID()
        defer {
            for name in ["cloudBackupConsent", "coachHistoryConsent"] {
                UserDefaults.standard.removeObject(forKey: AccountLocalStorage.key(name, userID: owner))
            }
        }
        AccountLocalStorage.write(true, name: "cloudBackupConsent", userID: owner)
        XCTAssertFalse(CoachHistoryPermission.isEnabled(userID: owner))
        AccountLocalStorage.write(true, name: "coachHistoryConsent", userID: owner)
        XCTAssertTrue(CoachHistoryPermission.isEnabled(userID: owner))
        XCTAssertFalse(CoachHistoryPermission.isEnabled(userID: UUID()))
        AccountLocalStorage.write(false, name: "coachHistoryConsent", userID: owner)
        XCTAssertFalse(CoachHistoryPermission.isEnabled(userID: owner))
    }

    private func clear(_ userID: UUID) {
        for name in TrainingBackupPayload.names + ["strengthActive", "phoneActive"] {
            UserDefaults.standard.removeObject(forKey: AccountLocalStorage.key(name, userID: userID))
        }
    }
}
