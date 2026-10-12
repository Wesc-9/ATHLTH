import XCTest
@testable import ATHLTH

final class ATHLTHPhoneStrengthPhaseTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func phase(
        workoutComplete: Bool = false,
        exerciseComplete: Bool = false,
        isResting: Bool = false,
        restEndsAt: Date? = nil,
        isTimedSet: Bool = false,
        timerStarted: Bool = false,
        timerRunning: Bool = false,
        timerRemaining: TimeInterval? = nil
    ) -> ATHLTHPhoneStrengthPhase {
        ATHLTHPhoneStrengthPhaseResolver.resolve(
            workoutComplete: workoutComplete,
            exerciseComplete: exerciseComplete,
            isResting: isResting,
            restEndsAt: restEndsAt,
            isTimedSet: isTimedSet,
            timerStarted: timerStarted,
            timerRunning: timerRunning,
            timerRemaining: timerRemaining,
            now: now
        )
    }

    func testRegularSetAndTimedSetHaveDifferentLabels() {
        XCTAssertEqual(phase(), .workingSet)
        XCTAssertEqual(phase(isTimedSet: true), .timedReady)
        XCTAssertEqual(
            phase(isTimedSet: true, timerStarted: true, timerRunning: true,
                  timerRemaining: 25), .timedRunning
        )
        XCTAssertEqual(
            phase(isTimedSet: true, timerStarted: true, timerRemaining: 25),
            .timedPaused
        )
        XCTAssertEqual(
            phase(isTimedSet: true, timerStarted: true, timerRunning: true,
                  timerRemaining: 0), .timedFinished
        )
    }

    func testExpiredRestIsReadyAndDoesNotAutoAdvance() {
        XCTAssertEqual(
            phase(isResting: true,
                  restEndsAt: now.addingTimeInterval(10)), .resting
        )
        XCTAssertEqual(
            phase(isResting: true,
                  restEndsAt: now.addingTimeInterval(-1)), .restReady
        )
        XCTAssertEqual(
            phase(exerciseComplete: true, isResting: true,
                  restEndsAt: now.addingTimeInterval(-1)), .restReady
        )
    }

    func testCompletedWorkoutOverridesPhase() {
        XCTAssertEqual(
            phase(workoutComplete: true, isResting: true,
                  restEndsAt: now.addingTimeInterval(15)), .workoutComplete
        )
        XCTAssertEqual(phase(exerciseComplete: true), .exerciseComplete)
    }

    func testMirrorClockStopsExtrapolatingAfterDisconnect() {
        let captured = now
        XCTAssertEqual(
            ATHLTHPhoneMirroredClock.elapsed(
                recorded: 90, capturedAt: captured,
                state: .running, now: now.addingTimeInterval(3)
            ), 93, accuracy: 0.001
        )
        XCTAssertEqual(
            ATHLTHPhoneMirroredClock.elapsed(
                recorded: 90, capturedAt: captured,
                state: .running, now: now.addingTimeInterval(20)
            ), 90, accuracy: 0.001
        )
    }

    func testPausedMirrorClockDoesNotAdvance() {
        XCTAssertEqual(
            ATHLTHPhoneMirroredClock.elapsed(
                recorded: 125, capturedAt: now,
                state: .paused, now: now.addingTimeInterval(2)
            ), 125, accuracy: 0.001
        )
    }

    func testMissingOrFutureSnapshotIsNotFresh() {
        XCTAssertFalse(
            ATHLTHPhoneMirroredClock.isFresh(
                snapshotAt: now, now: now.addingTimeInterval(30)
            )
        )
        XCTAssertFalse(
            ATHLTHPhoneMirroredClock.isFresh(
                snapshotAt: now.addingTimeInterval(10), now: now
            )
        )
    }
}
