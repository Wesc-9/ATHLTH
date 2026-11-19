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
            isEmbeddedRunningInterval: true,
            embeddedRunningTargetDistanceMeters: 1_500,
            isResting: false, restEndsAt: nil,
            currentExerciseComplete: false, hasNextExercise: true,
            allExercisesComplete: false, updatedAt: Date()
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
            isEmbeddedRunningInterval: true,
            embeddedRunningTargetDistanceMeters: 1_000,
            isResting: false, restEndsAt: nil,
            currentExerciseComplete: false, hasNextExercise: false,
            allExercisesComplete: false, updatedAt: Date()
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

    func testPersistedCorruptDistanceAnchorCannotCompleteOrDisplayProgress() {
        let negativeBaseline = ATHLTHHybridWatchDistanceAnchor(
            workoutID: UUID(), exerciseIndex: 0, setIndex: 0,
            baselineMeters: -100, activeElapsedAtStartSeconds: 25,
            targetMeters: 1_000
        )
        XCTAssertNil(negativeBaseline.measuredProgress(totalMeters: 1_100))
        XCTAssertFalse(negativeBaseline.hasReached(totalMeters: 1_100))
        XCTAssertNil(negativeBaseline.activeDurationSeconds(workoutActiveSeconds: 45))

        let nonfiniteTarget = ATHLTHHybridWatchDistanceAnchor(
            workoutID: UUID(), exerciseIndex: 0, setIndex: 0,
            baselineMeters: 10, activeElapsedAtStartSeconds: 25,
            targetMeters: .infinity
        )
        XCTAssertNil(nonfiniteTarget.measuredProgress(totalMeters: 2_000))
        XCTAssertFalse(nonfiniteTarget.hasReached(totalMeters: 2_000))

        let invalidClock = ATHLTHHybridWatchDistanceAnchor(
            workoutID: UUID(), exerciseIndex: 0, setIndex: 0,
            baselineMeters: 10, activeElapsedAtStartSeconds: -25,
            targetMeters: 1_000
        )
        XCTAssertNil(invalidClock.activeDurationSeconds(workoutActiveSeconds: 50))
        XCTAssertFalse(invalidClock.hasReached(totalMeters: 2_000))
    }

    func testDistanceAnchorRejectsInvalidSetIdentityAndInactivePhase() {
        var snap = WatchStrengthSessionSnapshot(
            workoutID: UUID(), title: "Outdoor", exerciseIndex: 0,
            exerciseCount: 1, exerciseName: "Outdoor Running",
            primaryMuscles: [], setIndex: 0, setCount: 1,
            setNumber: 1, completedSets: 0, totalSets: 1,
            draftReps: 0, draftWeightKilograms: 0, draftRestSeconds: 0,
            isEmbeddedRunningInterval: true,
            embeddedRunningTargetDistanceMeters: 1_000,
            isResting: false, restEndsAt: nil,
            currentExerciseComplete: false, hasNextExercise: false,
            allExercisesComplete: false, updatedAt: Date()
        )
        let anchor = ATHLTHHybridWatchDistanceAnchor.make(
            snapshot: snap, measuredTotalMeters: 10,
            activeElapsedSeconds: 50
        )
        XCTAssertNotNil(anchor)
        snap.isEmbeddedRunningInterval = false
        XCTAssertFalse(anchor?.matches(snap) ?? true)
        XCTAssertNil(ATHLTHHybridWatchDistanceAnchor.make(
            snapshot: snap, measuredTotalMeters: 10, activeElapsedSeconds: 50
        ))
        snap.isEmbeddedRunningInterval = true
        snap.isResting = true
        XCTAssertNil(ATHLTHHybridWatchDistanceAnchor.make(
            snapshot: snap, measuredTotalMeters: 10, activeElapsedSeconds: 50
        ))
        snap.isResting = false
        snap.exerciseIndex = 1
        XCTAssertNil(ATHLTHHybridWatchDistanceAnchor.make(
            snapshot: snap, measuredTotalMeters: 10, activeElapsedSeconds: 50
        ))
        snap.exerciseIndex = 0
        snap.setIndex = 1
        XCTAssertNil(ATHLTHHybridWatchDistanceAnchor.make(
            snapshot: snap, measuredTotalMeters: 10, activeElapsedSeconds: 50
        ))
    }
}
