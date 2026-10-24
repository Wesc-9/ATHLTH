import Foundation
import XCTest
@testable import ATHLTH

final class StrengthActiveExerciseQueueTests: XCTestCase {
    private func exercise(_ title: String, equipment: [String] = ["Barbell"]) -> Exercise {
        Exercise(
            id: UUID(),
            origin: .publicCatalog,
            ownerID: nil,
            name: title,
            instructions: [],
            primaryMuscles: ["Quadriceps"],
            secondaryMuscles: [],
            equipment: equipment,
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: true
        )
    }

    @MainActor
    func testDirectDragKeepsCurrentSetAndParentWatchWorkout() throws {
        let store = StrengthWorkoutStore()
        let watchID = UUID()
        store.startFreestyle(watchSessionID: watchID, captureDevice: .appleWatch)
        store.appendExercise(exercise("Knebøy"), sets: 3, reps: 8)
        store.appendExercise(exercise("Benkpress"), sets: 3, reps: 10)
        store.appendExercise(exercise("Markløft"), sets: 3, reps: 6)

        let original = try XCTUnwrap(store.activeWorkout)
        let exerciseIDs = original.exercises.map(\.id)
        let selectedID = try XCTUnwrap(store.currentExercise?.id)
        let setID = try XCTUnwrap(store.currentSet?.id)

        XCTAssertTrue(store.moveActiveExercise(exerciseIDs[2], before: exerciseIDs[0]))
        let after = try XCTUnwrap(store.activeWorkout)
        XCTAssertEqual(after.exercises.map(\.id),
                       [exerciseIDs[2], exerciseIDs[0], exerciseIDs[1]])
        XCTAssertEqual(after.id, original.id)
        XCTAssertEqual(after.watchSessionID, watchID)
        XCTAssertEqual(store.currentExercise?.id, selectedID)
        XCTAssertEqual(store.currentSet?.id, setID)
        XCTAssertFalse(store.moveActiveExercise(exerciseIDs[2], before: UUID()))
    }

    @MainActor
    func testDeleteOnlyUnrecordedExerciseAndKeepExistingResults() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        store.appendExercise(exercise("Benkpress"), sets: 2, reps: 8)
        store.completeCurrentDraftSet()
        store.appendExercise(exercise("Knebøy"), sets: 3, reps: 10)
        let existing = try XCTUnwrap(store.activeWorkout)
        let recordedID = existing.exercises[0].id
        let pendingID = existing.exercises[1].id
        XCTAssertFalse(store.canRemoveActiveExercise(recordedID))
        XCTAssertFalse(store.removeActiveExercise(recordedID))
        XCTAssertTrue(store.canRemoveActiveExercise(pendingID))
        XCTAssertTrue(store.removeActiveExercise(pendingID))
        let updated = try XCTUnwrap(store.activeWorkout)
        XCTAssertEqual(updated.id, existing.id)
        XCTAssertEqual(updated.exercises.count, 1)
        XCTAssertEqual(updated.exercises[0].id, recordedID)
        XCTAssertEqual(updated.exercises[0].sets.filter(\.isCompleted).count, 1)
    }

    @MainActor
    func testWarmupCanBeAddedAfterWorkoutStartsAndNeverCountsAsVolume() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        store.appendExercise(exercise("Benkpress"), sets: 1, reps: 8)
        store.completeCurrentDraftSet()
        store.appendExercise(exercise("Mobilisering", equipment: []),
                             sets: 2, reps: 12, warmUpSets: 2)
        let warm = try XCTUnwrap(store.activeWorkout?.exercises.last)
        XCTAssertTrue(warm.isWarmUpExercise)
        XCTAssertTrue(warm.sets.allSatisfy { $0.isWarmUp == true })
        XCTAssertTrue(store.moveActiveExercise(warm.id, before:
            store.activeWorkout!.exercises[0].id))
        XCTAssertEqual(store.activeWorkout?.exercises.first?.id, warm.id)
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 1)
    }

    @MainActor
    func testBarWeightIsMetadataNotAdditionalLoggedKilograms() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        store.appendExercise(exercise("Smithmaskin knebøy"), sets: 1, reps: 10)
        let id = try XCTUnwrap(store.currentExercise?.id)
        store.setDraft(reps: 10, weightKilograms: 60)
        XCTAssertTrue(store.setActiveExerciseBarWeight(id, kilograms: 20))
        XCTAssertEqual(store.draftWeightKilograms, 60, accuracy: 0.001)
        store.completeCurrentDraftSet()
        let result = try XCTUnwrap(store.activeWorkout?.exercises.first)
        XCTAssertEqual(result.barWeightKilograms, 20)
        XCTAssertEqual(result.sets[0].completedWeightKilograms, 60)
        XCTAssertEqual(store.activeWorkout?.totalVolumeKilograms ?? 0,
                       600, accuracy: 0.001)

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(StrengthExerciseLog.self,
                                               from: encoded)
        XCTAssertEqual(decoded.barWeightKilograms, 20)
        XCTAssertEqual(decoded.sets[0].completedWeightKilograms, 60)
        XCTAssertFalse(store.canRemoveActiveExercise(id))
    }
}
