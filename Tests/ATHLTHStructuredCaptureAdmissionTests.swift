import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHStructuredCaptureAdmissionTests: XCTestCase {
    func testStructuredWorkoutReservesOneSlotUntilExplicitRelease() throws {
        let suite = "ATHLTH.structured.admission.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            ATHLTHStructuredCaptureAdmission.switchAccount(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suite)
        }
        let owner = UUID(), workout = UUID()
        ATHLTHStructuredCaptureAdmission.switchAccount(owner, defaults: defaults)
        try ATHLTHStructuredCaptureAdmission.admit(
            workoutID: workout, userID: owner
        )
        XCTAssertEqual(ATHLTHStructuredCaptureAdmission.activeWorkoutID, workout)
        XCTAssertThrowsError(try ATHLTHWorkoutRecordingArbiter.reserveLaunch())
        XCTAssertFalse(ATHLTHWorkoutRecordingArbiter.mayStartStrength())
        XCTAssertFalse(ATHLTHWorkoutRecordingArbiter.mayStartRunning())
        XCTAssertThrowsError(try ATHLTHStructuredCaptureAdmission.admit(
            workoutID: UUID(), userID: owner
        ))
        ATHLTHStructuredCaptureAdmission.release(
            workoutID: workout, userID: owner
        )
        XCTAssertFalse(ATHLTHStructuredCaptureAdmission.hasActiveCapture)
    }

    func testDifferentAccountCannotReuseStructuredAdmission() throws {
        let suite = "ATHLTH.structured.accounts.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            ATHLTHStructuredCaptureAdmission.switchAccount(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suite)
        }
        let first = UUID(), second = UUID(), workout = UUID()
        ATHLTHStructuredCaptureAdmission.switchAccount(first, defaults: defaults)
        try ATHLTHStructuredCaptureAdmission.admit(
            workoutID: workout, userID: first
        )
        XCTAssertThrowsError(try ATHLTHStructuredCaptureAdmission.admit(
            workoutID: workout, userID: second
        ))
        ATHLTHStructuredCaptureAdmission.switchAccount(second, defaults: defaults)
        XCTAssertNil(ATHLTHStructuredCaptureAdmission.activeWorkoutID)
    }

    func testSavedCompletionReceiptIsIdempotentOnRetry() throws {
        let suite = "ATHLTH.structured.history.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let owner = UUID(), source = UUID()
        let firstID = UUID()
        let record = StructuredWorkoutCompletion(
            id: firstID, workoutTemplateID: nil,
            sourceWorkoutID: source, title: "Hybrid",
            category: "hybrid",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            endedAt: Date(timeIntervalSince1970: 1_800_000_900),
            completedBlockCount: 2, totalBlockCount: 2
        )
        XCTAssertTrue(StructuredWorkoutCompletionStore.save(
            record, userID: owner, defaults: defaults
        ))
        XCTAssertTrue(StructuredWorkoutCompletionStore.save(
            record, userID: owner, defaults: defaults
        ))
        let saved = AccountLocalStorage.read(
            [StructuredWorkoutCompletion].self,
            name: "structuredWorkoutHistory", userID: owner, defaults: defaults
        ) ?? []
        XCTAssertEqual(saved.filter { $0.id == firstID }.count, 1)
        XCTAssertEqual(saved.first?.sourceWorkoutID, source)
    }

    func testExpiredButDecodableCheckpointDoesNotBlockNewWorkouts() throws {
        let suite = "ATHLTH.structured.expired.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            ATHLTHStructuredCaptureAdmission.switchAccount(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suite)
        }
        let owner = UUID(), workout = UUID()
        let old = Date().addingTimeInterval(-9 * 86_400)
        let step = WorkoutTemplateBlock(
            sequence: 1, kind: .note, title: "Yoga",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 300,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
        let saved = ATHLTHStructuredWorkoutCheckpoint(
            workoutID: workout, savedAt: old,
            startedAt: old, stepEnteredAt: old,
            currentIndex: 0, completedIDs: [],
            results: [:], modeStarts: [:],
            executionBlocks: [step], emomWaiting: false,
            timedOutGroups: [], enteredReps: 0,
            enteredWeight: ""
        )
        let key = AccountLocalStorage.key(
            "structuredWorkoutInProgress.v1.\(workout.uuidString)",
            userID: owner
        )
        defaults.set(try JSONEncoder().encode(saved), forKey: key)
        ATHLTHStructuredCaptureAdmission.switchAccount(owner, defaults: defaults)
        XCTAssertFalse(ATHLTHStructuredCaptureAdmission.hasActiveCapture)
        XCTAssertNotNil(defaults.data(forKey: key))
    }

    func testCorruptStructuredCheckpointDoesNotGetOverwritten() throws {
        let suite = "ATHLTH.structured.corrupt.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            ATHLTHStructuredCaptureAdmission.switchAccount(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suite)
        }
        let owner = UUID(), workout = UUID()
        let key = AccountLocalStorage.key(
            "structuredWorkoutInProgress.v1.\(workout.uuidString)",
            userID: owner
        )
        let raw = Data("unknown future checkpoint".utf8)
        defaults.set(raw, forKey: key)
        ATHLTHStructuredCaptureAdmission.switchAccount(owner, defaults: defaults)
        XCTAssertTrue(ATHLTHStructuredCaptureAdmission.hasActiveCapture)
        XCTAssertThrowsError(try ATHLTHStructuredCaptureAdmission.admit(
            workoutID: workout, userID: owner
        ))
        XCTAssertEqual(defaults.data(forKey: key), raw)
    }

    func testReadOnlyActiveCheckpointRejectsOtherAccountAndAlteredBytes() throws {
        let suite = "ATHLTH.structured.original.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            ATHLTHStructuredCaptureAdmission.switchAccount(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suite)
        }
        let owner = UUID(), id = UUID()
        let now = Date()
        var yoga = WorkoutTemplateBlock(
            sequence: 1, kind: .note, title: "Yoga",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 600,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
        yoga.wellnessKind = .yoga
        let checkpoint = ATHLTHStructuredWorkoutCheckpoint(
            workoutID: id, savedAt: now,
            startedAt: now, stepEnteredAt: now,
            currentIndex: 0, completedIDs: [], results: [:],
            modeStarts: [:], executionBlocks: [yoga],
            emomWaiting: false, timedOutGroups: [],
            enteredReps: 0, enteredWeight: ""
        )
        let key = AccountLocalStorage.key(
            "structuredWorkoutInProgress.v1.\(id.uuidString)", userID: owner
        )
        defaults.set(try JSONEncoder().encode(checkpoint), forKey: key)
        ATHLTHStructuredCaptureAdmission.switchAccount(owner, defaults: defaults)
        XCTAssertEqual(ATHLTHStructuredCaptureAdmission.activeCheckpoint(
            for: owner, defaults: defaults
        )?.workoutID, id)
        XCTAssertNil(ATHLTHStructuredCaptureAdmission.activeCheckpoint(
            for: UUID(), defaults: defaults
        ))
        defaults.set(Data("unknown schema".utf8), forKey: key)
        XCTAssertNil(ATHLTHStructuredCaptureAdmission.activeCheckpoint(
            for: owner, defaults: defaults
        ))
        XCTAssertTrue(ATHLTHStructuredCaptureAdmission.hasActiveCapture)
    }

    func testStructuredClockFreezesElapsedTimeAndRejectsCorruption() {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let pause = start.addingTimeInterval(45)
        XCTAssertEqual(ATHLTHStructuredWorkoutClock.elapsed(
            start: start, now: start.addingTimeInterval(900),
            pause: pause, pausedSeconds: 0
        ), 45)
        XCTAssertEqual(ATHLTHStructuredWorkoutClock.resumeOffset(
            from: pause, at: start.addingTimeInterval(900)
        ), 855)
        XCTAssertEqual(ATHLTHStructuredWorkoutClock.elapsed(
            start: start, now: start.addingTimeInterval(910),
            pause: nil, pausedSeconds: 855
        ), 55)
        XCTAssertNil(ATHLTHStructuredWorkoutClock.elapsed(
            start: start, now: start.addingTimeInterval(10),
            pause: nil, pausedSeconds: 999
        ))
        XCTAssertNil(ATHLTHStructuredWorkoutClock.elapsed(
            start: start, now: start.addingTimeInterval(10),
            pause: nil, pausedSeconds: .nan
        ))
    }


    func testActiveRecoveryNeverCreatesFreshCheckpointOverExistingAdmission() {
        XCTAssertTrue(
            ATHLTHStructuredRecoveryWritePolicy.canCreateFreshCheckpoint(
                alreadyAdmitted: false, restored: false
            )
        )
        XCTAssertFalse(
            ATHLTHStructuredRecoveryWritePolicy.canCreateFreshCheckpoint(
                alreadyAdmitted: true, restored: false
            )
        )
        XCTAssertFalse(
            ATHLTHStructuredRecoveryWritePolicy.canCreateFreshCheckpoint(
                alreadyAdmitted: true, restored: true
            )
        )
        XCTAssertFalse(
            ATHLTHStructuredRecoveryWritePolicy.canCreateFreshCheckpoint(
                alreadyAdmitted: false, restored: true
            )
        )
    }


    func testStructuredRecoveryNeverReassignsOriginalPlan() {
        let original = UUID(), wrong = UUID()
        XCTAssertTrue(ATHLTHStructuredPlanRecoveryPolicy.allowsRestore(
            savedPlanID: original, requestedPlanID: original
        ))
        XCTAssertTrue(ATHLTHStructuredPlanRecoveryPolicy.allowsRestore(
            savedPlanID: original, requestedPlanID: nil
        ))
        XCTAssertEqual(ATHLTHStructuredPlanRecoveryPolicy.effectivePlanID(
            savedPlanID: original, requestedPlanID: nil
        ), original)
        XCTAssertFalse(ATHLTHStructuredPlanRecoveryPolicy.allowsRestore(
            savedPlanID: original, requestedPlanID: wrong
        ))
        XCTAssertNil(ATHLTHStructuredPlanRecoveryPolicy.effectivePlanID(
            savedPlanID: original, requestedPlanID: wrong
        ))
        // Previous release checkpoints did not have a plan reference.
        // They must remain restorable without dropping their original progress.
        XCTAssertTrue(ATHLTHStructuredPlanRecoveryPolicy.allowsRestore(
            savedPlanID: nil, requestedPlanID: wrong
        ))
    }


    func testStructuredOriginalTitleAndPlanSurvivePersistedCheckpoint() throws {
        let plan = UUID(), id = UUID()
        let started = Date(timeIntervalSince1970: 1_900_000_000)
        let step = WorkoutTemplateBlock(
            sequence: 1, kind: .note, title: "Mobility",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 180,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
        let checkpoint = ATHLTHStructuredWorkoutCheckpoint(
            workoutID: id, sourcePlanID: plan, sourceTitle: "Mobility plan",
            savedAt: started, startedAt: started,
            stepEnteredAt: started, currentIndex: 0,
            completedIDs: [], results: [:], modeStarts: [:],
            executionBlocks: [step], emomWaiting: false,
            timedOutGroups: [], enteredReps: 0, enteredWeight: ""
        )
        let restored = try JSONDecoder().decode(
            ATHLTHStructuredWorkoutCheckpoint.self,
            from: JSONEncoder().encode(checkpoint)
        )
        XCTAssertEqual(restored.workoutID, id)
        XCTAssertEqual(restored.sourcePlanID, plan)
        XCTAssertEqual(restored.sourceTitle, "Mobility plan")
    }

}
