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

    @MainActor
    func testRepeatedStrengthStartKeepsUnfinishedWorkout() {
        let owner = UUID()
        defer { clear(owner) }
        let store = StrengthWorkoutStore()
        store.switchAccount(owner)
        store.startFreestyle(watchSessionID: nil)

        let firstID = store.activeWorkout?.id
        XCTAssertNotNil(firstID)

        // A second button tap must not silently discard the first log.
        store.startFreestyle(watchSessionID: nil)
        XCTAssertEqual(store.activeWorkout?.id, firstID)

        let planned = PlannedSession(
            id: UUID(),
            title: "Second session",
            kind: .strength,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil,
            runningWorkout: nil
        )
        store.start(
            session: planned,
            watchSessionID: nil,
            trackingMode: .simple,
            captureDevice: .iPhone
        )
        XCTAssertEqual(store.activeWorkout?.id, firstID)
    }

    @MainActor
    func testBasicStrengthKeepsBasicModeWhenAddingExercise() {
        let owner = UUID()
        defer { clear(owner) }

        let store = StrengthWorkoutStore()
        store.switchAccount(owner)
        store.startFreestyle(
            watchSessionID: nil,
            trackingMode: .simple,
            captureDevice: .iPhone
        )

        let exercise = Exercise(
            id: UUID(),
            origin: .custom,
            ownerID: owner,
            name: "Goblet Squat",
            instructions: [],
            primaryMuscles: ["Quads"],
            secondaryMuscles: ["Glutes"],
            equipment: [],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: false
        )

        store.appendExercise(exercise)

        XCTAssertEqual(
            store.activeWorkout?.trackingMode,
            .simple
        )
        XCTAssertEqual(
            store.activeWorkout?.exercises.count,
            1
        )
    }

    @MainActor
    func testAdvancedStrengthConfigurationPersistsAndCanDisableAutoRest() {
        let owner = UUID()
        defer { clear(owner) }

        var configuration =
            StrengthAdvancedConfiguration.standard
        configuration.keepScreenAwake = true
        configuration.inputMode = .iPhone
        configuration.restCues.automaticRestTimer = false
        configuration.audioCoach.enabled = true

        let store = StrengthWorkoutStore()
        store.switchAccount(owner)
        store.startFreestyle(
            watchSessionID: nil,
            trackingMode: .advanced,
            captureDevice: .iPhone,
            advancedConfiguration:
                configuration
        )

        let exercise = Exercise(
            id: UUID(),
            origin: .custom,
            ownerID: owner,
            name: "Bench Press",
            instructions: [],
            primaryMuscles: ["Chest"],
            secondaryMuscles: ["Triceps"],
            equipment: [],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: false
        )

        store.appendExercise(
            exercise,
            sets: 2,
            reps: 8,
            restSeconds: 90
        )
        store.completeCurrentSet(
            reps: 8,
            weightKilograms: 60,
            rpe: 7
        )

        XCTAssertNil(store.restEndsAt)
        XCTAssertEqual(
            store.activeWorkout?
                .advancedConfiguration,
            configuration
        )

        let reopened = StrengthWorkoutStore()
        reopened.switchAccount(owner)

        XCTAssertEqual(
            reopened.activeWorkout?
                .advancedConfiguration,
            configuration
        )
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

    func testLegacyPhoneWorkoutStillDecodesWithoutPauseTimeline() throws {
        let start = Date(timeIntervalSince1970: 2_000)
        let legacy = PhoneWorkout(
            walking: true,
            start: start,
            accumulatedSeconds: 180,
            resumedAt: nil,
            lastCheckpoint: start.addingTimeInterval(180),
            pauses: nil
        )

        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(
            PhoneWorkout.self,
            from: data
        )

        XCTAssertEqual(decoded.id, legacy.id)
        XCTAssertEqual(decoded.accumulatedSeconds, 180)
        XCTAssertNil(decoded.pauses)
    }

    func testPhoneWorkoutPauseTimelineRoundTrips() throws {
        let start = Date(timeIntervalSince1970: 3_000)
        let pauseStart = start.addingTimeInterval(60)
        let pauseEnd = pauseStart.addingTimeInterval(30)
        let workout = PhoneWorkout(
            walking: false,
            start: start,
            accumulatedSeconds: 120,
            resumedAt: nil,
            lastCheckpoint: pauseEnd,
            pauses: [
                PhoneWorkoutPauseInterval(
                    startedAt: pauseStart,
                    endedAt: pauseEnd
                )
            ]
        )

        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(
            PhoneWorkout.self,
            from: data
        )

        XCTAssertEqual(decoded.pauses, workout.pauses)
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

    @MainActor
    func testLiveSwapOfNextSetPreservesCompletedAndLaterPlannedSets() {
        let owner = UUID()
        defer { clear(owner) }

        let store = StrengthWorkoutStore()
        store.switchAccount(owner)

        let barbell = Exercise(
            id: UUID(),
            origin: .custom,
            ownerID: owner,
            name: "Barbell Bench Press",
            instructions: [],
            primaryMuscles: ["Chest"],
            secondaryMuscles: ["Triceps"],
            equipment: [],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: false
        )
        let dumbbell = Exercise(
            id: UUID(),
            origin: .custom,
            ownerID: owner,
            name: "Dumbbell Bench Press",
            instructions: [],
            primaryMuscles: ["Chest"],
            secondaryMuscles: ["Triceps"],
            equipment: [],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: false
        )

        store.startFreestyle(watchSessionID: nil)
        store.appendExercise(
            barbell,
            sets: 3,
            reps: 8,
            loadKind: .weightKilograms,
            targetWeightKilograms: 60
        )
        store.completeCurrentSet(
            reps: 8,
            weightKilograms: 60,
            rpe: 7
        )

        let originalCompletedID = store.activeWorkout?
            .exercises.first?.sets.first?.id
        let originalFinalID = store.activeWorkout?
            .exercises.first?.sets.last?.id

        store.substituteCurrentExercise(
            with: dumbbell,
            scope: .nextSetOnly
        )

        let exercises = store.activeWorkout?.exercises ?? []
        XCTAssertEqual(exercises.count, 3)
        XCTAssertEqual(exercises[0].exercise.name, "Barbell Bench Press")
        XCTAssertEqual(exercises[0].sets.map(\.id), [originalCompletedID].compactMap { $0 })
        XCTAssertEqual(exercises[0].sets.first?.completedWeightKilograms, 60)
        XCTAssertEqual(exercises[1].exercise.name, "Dumbbell Bench Press")
        XCTAssertEqual(exercises[1].sets.count, 1)
        XCTAssertNil(exercises[1].sets.first?.plannedWeightKilograms)
        XCTAssertNil(exercises[1].sets.first?.plannedResistanceLevel)
        XCTAssertNil(exercises[1].plannedExerciseID)
        XCTAssertEqual(exercises[2].exercise.name, "Barbell Bench Press")
        XCTAssertEqual(exercises[2].sets.map(\.id), [originalFinalID].compactMap { $0 })
        XCTAssertEqual(exercises[2].sets.first?.plannedWeightKilograms, 60)
    }

    @MainActor
    func testLiveSwapOfAllRemainingDoesNotCarryOldEquipmentLoad() {
        let owner = UUID()
        defer { clear(owner) }

        let store = StrengthWorkoutStore()
        store.switchAccount(owner)
        let original = Exercise(
            id: UUID(),
            origin: .custom,
            ownerID: owner,
            name: "Barbell Press",
            instructions: [],
            primaryMuscles: ["Chest"],
            secondaryMuscles: [],
            equipment: [],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: false
        )
        let replacement = Exercise(
            id: UUID(),
            origin: .custom,
            ownerID: owner,
            name: "Machine Chest Press",
            instructions: [],
            primaryMuscles: ["Chest"],
            secondaryMuscles: [],
            equipment: [],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: false
        )
        store.startFreestyle(watchSessionID: nil)
        store.appendExercise(
            original,
            sets: 3,
            reps: 10,
            loadKind: .weightKilograms,
            targetWeightKilograms: 50
        )
        store.completeCurrentSet(
            reps: 10,
            weightKilograms: 50,
            rpe: 7
        )

        store.substituteCurrentExercise(
            with: replacement,
            scope: .allRemaining
        )

        let exercises = store.activeWorkout?.exercises ?? []
        XCTAssertEqual(exercises.count, 2)
        XCTAssertEqual(exercises[0].sets.count, 1)
        XCTAssertEqual(exercises[0].sets.first?.completedWeightKilograms, 50)
        XCTAssertEqual(exercises[1].sets.count, 2)
        XCTAssertTrue(exercises[1].sets.allSatisfy {
            $0.plannedWeightKilograms == nil &&
            $0.plannedResistanceLevel == nil &&
            !$0.isCompleted
        })
    }

    @MainActor
    func testPartiallyFinishedStrengthLogPreservesUnfinishedSets() {
        let owner = UUID()
        defer { clear(owner) }
        let store = StrengthWorkoutStore()
        store.switchAccount(owner)
        store.startFreestyle(watchSessionID: nil)

        let exercise = Exercise(
            id: UUID(),
            origin: .custom,
            ownerID: owner,
            name: "Bench Press",
            instructions: [],
            primaryMuscles: ["Chest"],
            secondaryMuscles: [],
            equipment: [],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: false
        )
        store.appendExercise(
            exercise,
            sets: 3,
            reps: 8,
            loadKind: .weightKilograms,
            targetWeightKilograms: 60
        )
        XCTAssertEqual(store.activeWorkout?.remainingSetCount, 3)

        store.completeCurrentSet(
            reps: 8,
            weightKilograms: 60,
            rpe: 7
        )
        XCTAssertEqual(store.activeWorkout?.remainingSetCount, 2)
        store.finish()
        XCTAssertNil(store.activeWorkout)
        XCTAssertEqual(store.completedWorkout?.remainingSetCount, 2)
        XCTAssertEqual(store.completedWorkout?.totalCompletedSets, 1)
        XCTAssertEqual(store.workoutHistory.count, 1)
        XCTAssertEqual(store.workoutHistory.first?.remainingSetCount, 2)
        XCTAssertEqual(
            store.workoutHistory.first?.exercises.first?.sets.first?.completedWeightKilograms,
            60
        )
    }

    private func clear(_ userID: UUID) {
        for name in TrainingBackupPayload.names + ["strengthActive", "phoneActive"] {
            UserDefaults.standard.removeObject(forKey: AccountLocalStorage.key(name, userID: userID))
        }
    }
}
