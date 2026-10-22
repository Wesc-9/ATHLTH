import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHHybridStrengthSessionTests: XCTestCase {
    private func session(
        title: String,
        kind: WorkoutKind,
        runningWorkout: RunningWorkoutTemplate? = nil
    ) -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: title,
            kind: kind,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: "",
            runningWorkout: runningWorkout
        )
    }

    @MainActor
    func testAppendingIntervalsKeepsParentWorkoutAndWatchIdentifiers() {
        let strength = StrengthWorkoutStore()
        let watchID = UUID()
        strength.start(
            session: session(title: "Strength", kind: .strength),
            watchSessionID: watchID,
            trackingMode: .simple,
            captureDevice: .appleWatch
        )
        let initialWorkoutID = strength.activeWorkout?.id
        let template = RunningWorkoutLibraryStore.builtInTemplates.first {
            $0.title.contains("4 × 4")
        }
        XCTAssertNotNil(template)
        guard let template else { return }

        XCTAssertTrue(strength.appendWorkoutDuringSession(
            session(title: "4 × 4", kind: .running, runningWorkout: template),
            startNow: true
        ))
        XCTAssertEqual(strength.activeWorkout?.id, initialWorkoutID)
        XCTAssertEqual(strength.activeWorkout?.watchSessionID, watchID)
        XCTAssertEqual(strength.activeWorkout?.exercises.count, 1)
        XCTAssertEqual(strength.currentExercise?.isEmbeddedRunningInterval, true)
        XCTAssertTrue(strength.currentSet?.resolvedTargetKind == .time)
    }

    @MainActor
    func testUnsupportedWorkoutNeverChangesParentRecording() {
        let strength = StrengthWorkoutStore()
        strength.start(
            session: session(title: "Strength", kind: .strength),
            watchSessionID: nil,
            trackingMode: .simple,
            captureDevice: .iPhone
        )
        let id = strength.activeWorkout?.id
        XCTAssertFalse(strength.appendWorkoutDuringSession(
            session(title: "Empty", kind: .strength),
            startNow: true
        ))
        XCTAssertEqual(strength.activeWorkout?.id, id)
        XCTAssertEqual(strength.activeWorkout?.exercises.count, 0)
    }

    @MainActor
    func testQueuedIntervalKeepsCurrentExerciseUnchanged() {
        let strength = StrengthWorkoutStore()
        strength.start(
            session: session(title: "Strength", kind: .strength),
            watchSessionID: nil,
            trackingMode: .simple,
            captureDevice: .iPhone
        )
        guard let template = RunningWorkoutLibraryStore.builtInTemplates.first(
            where: { $0.title.contains("4 × 4") }
        ) else {
            XCTFail("Built-in 4×4 is required")
            return
        }
        XCTAssertTrue(strength.appendWorkoutDuringSession(
            session(title: "Queued", kind: .running, runningWorkout: template),
            startNow: false
        ))
        XCTAssertEqual(strength.activeWorkout?.exercises.count, 1)
        XCTAssertEqual(strength.currentSet?.completedAt, nil)
    }
}
