import Foundation
import XCTest
@testable import ATHLTH

final class StrengthSkipSetWatchTests: XCTestCase {
    private func exercise() -> Exercise {
        Exercise(
            id: UUID(),
            origin: .publicCatalog,
            ownerID: nil,
            name: "Squat",
            instructions: [],
            primaryMuscles: ["Quadriceps"],
            secondaryMuscles: [],
            equipment: ["Barbell"],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: true
        )
    }

    @MainActor
    func testSkippingPendingSetDoesNotCreateTrainingVolume() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: UUID(), captureDevice: .appleWatch)
        store.appendExercise(exercise(), sets: 3, reps: 8)
        XCTAssertEqual(store.watchSnapshot?.setCount, 3)
        XCTAssertTrue(store.skipCurrentSet())
        XCTAssertEqual(store.watchSnapshot?.setCount, 2)
        XCTAssertEqual(store.watchSnapshot?.skippedSets, 1)
        XCTAssertEqual(store.watchSnapshot?.totalSets, 3)
        XCTAssertEqual(store.watchSnapshot?.completedSets, 0)
        XCTAssertEqual(store.activeWorkout?.exercises[0].skippedPlannedSetCount, 1)
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 0)
        XCTAssertEqual(store.activeWorkout?.exercises[0].sets.reduce(0.0) {
            $0 + $1.volumeKilograms
        }, 0)
    }

    @MainActor
    func testCompletedSetCannotBeSkippedAgain() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: UUID(), captureDevice: .appleWatch)
        store.appendExercise(exercise(), sets: 1, reps: 8)
        store.completeCurrentDraftSet()
        XCTAssertFalse(store.skipCurrentSet())
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 1)
        XCTAssertEqual(store.watchSnapshot?.skippedSets, 0)
    }

    func testWatchCanSkipSetEvenWhenIPhoneOwnsDraftValues() {
        XCTAssertTrue(ATHLTHStrengthWatchControlPolicy.permits(
            .skipSet, whenIPhoneControls: true
        ))
        XCTAssertFalse(ATHLTHStrengthWatchControlPolicy.permits(
            .updateDraft, whenIPhoneControls: true
        ))
    }

    func testPhoneCapturedWorkoutAllowsWatchSetLoggingForBothAndWatchModes() {
        XCTAssertTrue(ATHLTHStrengthWatchControlPolicy.acceptsSetCommands(
            captureDevice: .iPhone, inputMode: .both
        ))
        XCTAssertTrue(ATHLTHStrengthWatchControlPolicy.acceptsSetCommands(
            captureDevice: .iPhone, inputMode: .appleWatch
        ))
        XCTAssertFalse(ATHLTHStrengthWatchControlPolicy.acceptsSetCommands(
            captureDevice: .iPhone, inputMode: .iPhone
        ))
        XCTAssertTrue(ATHLTHStrengthWatchControlPolicy.acceptsSetCommands(
            captureDevice: .appleWatch, inputMode: .both
        ))
    }
}
