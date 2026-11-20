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
}
