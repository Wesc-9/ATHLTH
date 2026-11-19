import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHHybridWatchDistanceAnchorTests: XCTestCase {
    func testDistanceGoalUsesMeasuredProgressAndNeverElapsedTime() throws {
        let id = UUID()
        var snap = WatchStrengthSessionSnapshot(
            workoutID: id, title: "Outdoor", exerciseIndex: 0,
            exerciseCount: 2, exerciseName: "Outdoor Running",
            primaryMuscles: [], setIndex: 0, setCount: 1,
            setNumber: 1, completedSets: 0, totalSets: 1,
            draftReps: 0, draftWeightKilograms: 0, draftRestSeconds: 0,
            embeddedRunningTargetDistanceMeters: 1_500,
            isResting: false, restEndsAt: nil,
            currentExerciseComplete: false, hasNextExercise: true,
            allExercisesComplete: false, updatedAt: Date(),
            isEmbeddedRunningInterval: true
        )
        let anchor = try XCTUnwrap(ATHLTHHybridWatchDistanceAnchor.make(
            snapshot: snap, measuredTotalMeters: 2_000,
            activeElapsedSeconds: 300
        ))
        XCTAssertTrue(anchor.matches(snap))
        XCTAssertFalse(anchor.hasReached(totalMeters: 3_499))
        XCTAssertTrue(anchor.hasReached(totalMeters: 3_500))
        XCTAssertFalse(anchor.hasReached(totalMeters: .infinity))
        XCTAssertFalse(anchor.hasReached(totalMeters: 1_900))
        XCTAssertEqual(anchor.activeDurationSeconds(workoutActiveSeconds: 425), 125)
        XCTAssertNil(anchor.activeDurationSeconds(workoutActiveSeconds: 299))
        let restored = try JSONDecoder().decode(
            ATHLTHHybridWatchDistanceAnchor.self,
            from: JSONEncoder().encode(anchor)
        )
        XCTAssertEqual(restored, anchor)
        snap.setIndex = 1
        XCTAssertFalse(anchor.matches(snap))
        snap.setIndex = 0
        snap.exerciseIndex = 1
        XCTAssertFalse(anchor.matches(snap))
        snap.exerciseIndex = 0
        snap.workoutID = UUID()
        XCTAssertFalse(anchor.matches(snap))
    }

    func testMissingOrUnsafeGPSDistanceCannotStartGoal() {
        var snap = WatchStrengthSessionSnapshot(
            workoutID: UUID(), title: "Outdoor", exerciseIndex: 0,
            exerciseCount: 1, exerciseName: "Outdoor Running",
            primaryMuscles: [], setIndex: 0, setCount: 1,
            setNumber: 1, completedSets: 0, totalSets: 1,
            draftReps: 0, draftWeightKilograms: 0, draftRestSeconds: 0,
            embeddedRunningTargetDistanceMeters: 1_000,
            isResting: false, restEndsAt: nil,
            currentExerciseComplete: false, hasNextExercise: false,
            allExercisesComplete: false, updatedAt: Date(),
            isEmbeddedRunningInterval: true
        )
        XCTAssertNil(ATHLTHHybridWatchDistanceAnchor.make(
            snapshot: snap, measuredTotalMeters: .infinity,
            activeElapsedSeconds: 1
        ))
        snap.embeddedRunningTargetDistanceMeters = 0
        XCTAssertNil(ATHLTHHybridWatchDistanceAnchor.make(
            snapshot: snap, measuredTotalMeters: 0,
            activeElapsedSeconds: 1
        ))
        snap.embeddedRunningTargetDistanceMeters = 100_000
        XCTAssertNil(ATHLTHHybridWatchDistanceAnchor.make(
            snapshot: snap, measuredTotalMeters: 0,
            activeElapsedSeconds: 1
        ))
    }
}
