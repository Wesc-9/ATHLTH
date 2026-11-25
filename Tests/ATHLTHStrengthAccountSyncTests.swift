import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHStrengthAccountSyncTests: XCTestCase {
    private func makeWorkout(id: UUID = UUID()) -> StrengthWorkoutLog {
        let finished = Date(timeIntervalSince1970: 2_050_000_000)
        let set = StrengthSetLog(
            id: UUID(),
            setNumber: 1,
            plannedReps: 8,
            plannedWeightKilograms: 25,
            completedReps: 8,
            completedWeightKilograms: 25,
            rpe: 7,
            completedAt: finished,
            restSeconds: 60,
            plannedNote: "Do not synchronize medical notes",
            rir: 3,
            watchAverageHeartRateBPM: 126,
            watchMaximumHeartRateBPM: 154
        )
        var snapshot = ExerciseSnapshot(
            name: "Dumbbell Press",
            instructions: ["Private instructor note"],
            primaryMuscles: ["shoulders"],
            secondaryMuscles: [],
            equipment: ["dumbbells"],
            imageURL: nil
        )
        snapshot.libraryExerciseID = UUID()
        snapshot.coachLoadBasis = .kilogramsPerHand
        let exercise = StrengthExerciseLog(
            id: UUID(),
            plannedExerciseID: nil,
            exercise: snapshot,
            sets: [set],
            completedAt: finished,
            targetHeartRateZone: 5
        )
        return StrengthWorkoutLog(
            id: id,
            plannedSessionID: UUID(),
            watchSessionID: UUID(),
            captureDevice: .iPhone,
            trackingMode: .advanced,
            title: "Strength",
            startedAt: finished.addingTimeInterval(-3600),
            endedAt: finished,
            exercises: [exercise],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: UUID(),
                duration: 3600,
                activeCalories: 650,
                averageHeartRate: 145,
                maxHeartRate: 182
            ),
            liveHeartRateTargetZone: 5
        )
    }

    func testAutomaticSyncDocumentExcludesRawSensorAndHealthFields() throws {
        let workout = makeWorkout()
        let document = try XCTUnwrap(
            ATHLTHStrengthSyncDocument(workout: workout)
        )
        let bytes = try JSONEncoder().encode(document)
        let encoded = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        for forbidden in [
            "healthMetrics", "healthKitWorkoutUUID",
            "watchSessionID", "plannedTrainingPlace",
            "liveHeartRateTargetZone", "watchAverageHeartRateBPM",
            "watchMaximumHeartRateBPM", "plannedNote",
            "targetHeartRateZone", "hybridTargetHeartRateZone"
        ] {
            XCTAssertFalse(
                encoded.contains("\"\(forbidden)\""),
                "Unexpected field uploaded: \(forbidden)"
            )
        }
        XCTAssertTrue(encoded.contains("\"completedWeightKilograms\""))
        XCTAssertTrue(encoded.contains("\"coachLoadBasis\""))
        XCTAssertTrue(encoded.contains("\"completedReps\""))
        XCTAssertTrue(document.exercises[0].exercise.instructions.isEmpty)
        XCTAssertEqual(document.exercises[0].sets.first?.rir, 3)
    }

    func testSyncedWorkoutReconstructsOnlyTrainingHistory() throws {
        let source = makeWorkout()
        let document = try XCTUnwrap(
            ATHLTHStrengthSyncDocument(workout: source)
        )
        let received = try JSONDecoder().decode(
            ATHLTHStrengthSyncDocument.self,
            from: JSONEncoder().encode(document)
        ).asWorkout()
        XCTAssertEqual(received.id, source.id)
        XCTAssertEqual(received.plannedSessionID, source.plannedSessionID)
        XCTAssertEqual(
            received.exercises.first?.exercise.coachLoadBasis,
            .kilogramsPerHand
        )
        XCTAssertEqual(
            received.exercises.first?.sets.first?.completedWeightKilograms,
            25
        )
        XCTAssertNil(received.healthMetrics.averageHeartRate)
        XCTAssertNil(received.healthMetrics.healthKitWorkoutUUID)
        XCTAssertNil(received.watchSessionID)
        XCTAssertNil(received.exercises.first?.targetHeartRateZone)
    }

    func testIncompleteWorkoutsAreNeverUploaded() {
        var running = makeWorkout()
        running.endedAt = nil
        XCTAssertNil(ATHLTHStrengthSyncDocument(workout: running))
    }

    @MainActor
    func testRecordProjectionsInvalidateWhenHistoryOrAccountChanges() throws {
        let owner = UUID(), other = UUID()
        let store = StrengthWorkoutStore()
        store.switchAccount(owner)
        defer {
            store.switchAccount(nil)
            UserDefaults.standard.removeObject(forKey: AccountLocalStorage.key("strengthHistory", userID: owner))
            UserDefaults.standard.removeObject(forKey: AccountLocalStorage.key("strengthHistory", userID: other))
        }
        XCTAssertTrue(store.personalRecords.isEmpty)
        XCTAssertTrue(store.repPersonalRecords.isEmpty)
        _ = try store.mergeAccountSyncedWorkouts([makeWorkout()], for: owner)
        XCTAssertFalse(store.personalRecords.isEmpty)
        XCTAssertFalse(store.repPersonalRecords.isEmpty)
        store.switchAccount(other)
        XCTAssertTrue(store.personalRecords.isEmpty)
        XCTAssertTrue(store.repPersonalRecords.isEmpty)
        store.switchAccount(owner)
        XCTAssertFalse(store.personalRecords.isEmpty)
        XCTAssertFalse(store.repPersonalRecords.isEmpty)
    }

    @MainActor
    func testAccountMergeIsAutomaticDeduplicatedAndDoesNotReplaceLocalHealth() throws {
        let owner = UUID()
        let store = StrengthWorkoutStore()
        store.switchAccount(owner)
        defer {
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key(
                    "strengthHistory", userID: owner
                )
            )
        }
        let original = makeWorkout()
        XCTAssertEqual(
            try store.mergeAccountSyncedWorkouts([original], for: owner), 1
        )
        let cloud = try XCTUnwrap(
            ATHLTHStrengthSyncDocument(workout: original)
        ).asWorkout()
        XCTAssertEqual(
            try store.mergeAccountSyncedWorkouts([cloud], for: owner), 0
        )
        XCTAssertEqual(store.workoutHistory.count, 1)
        // The local full workout is authoritative, even if the cloud
        // copy deliberately contains no HealthKit fields.
        XCTAssertEqual(
            store.workoutHistory.first?.healthMetrics.averageHeartRate,
            145
        )
        XCTAssertThrowsError(
            try store.mergeAccountSyncedWorkouts([cloud], for: UUID())
        )
        XCTAssertEqual(store.workoutHistory.count, 1)
    }
}
