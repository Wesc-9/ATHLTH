import Foundation
import XCTest
@testable import ATHLTH

final class StrengthTimedSetCountdownTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_900_000_000)

    private func countdown(
        seconds: Int = 300,
        started: Date? = nil
    ) -> StrengthTimedSetCountdown {
        StrengthTimedSetCountdown(
            workoutID: UUID(),
            exerciseID: UUID(),
            setID: UUID(),
            targetSeconds: seconds,
            secondsAtPause: TimeInterval(seconds),
            resumedAt: started
        )
    }

    func testTimeTargetsAreEditedInMinutesButRemainSecondsInternally() {
        XCTAssertEqual(StrengthTimedSetMinuteInput.minutes(for: 300), 5)
        XCTAssertEqual(StrengthTimedSetMinuteInput.seconds(for: 5), 300)
        XCTAssertEqual(StrengthTimedSetMinuteInput.minutes(for: 90), 2)
        XCTAssertEqual(StrengthTimedSetMinuteInput.seconds(for: 0), 60)
        XCTAssertEqual(StrengthTimedSetMinuteInput.seconds(for: 121), 7_200)
    }

    func testManualFinishCanRecordActualTimeBeforeOrAfterCountdown() {
        let timer = countdown(started: base)
        let early = base.addingTimeInterval(199)
        let late = base.addingTimeInterval(379)
        XCTAssertEqual(timer.secondsRemaining(at: early), 101)
        XCTAssertEqual(timer.elapsedSeconds(at: early), 199)
        XCTAssertFalse(timer.isFinished(at: early))
        XCTAssertEqual(timer.secondsRemaining(at: late), 0)
        XCTAssertEqual(timer.elapsedSeconds(at: late), 379)
        XCTAssertTrue(timer.isFinished(at: late))
        // The countdown never advances the set on its own: the athlete
        // completes it explicitly from iPhone or the Watch command.
    }

    func testWatchCanStartOrFinishTimedSetWhenIPhoneControlsTargets() {
        XCTAssertTrue(ATHLTHStrengthWatchControlPolicy.permits(
            .skipRestAndStartTimedSet, whenIPhoneControls: true
        ))
        XCTAssertTrue(ATHLTHStrengthWatchControlPolicy.permits(
            .startTimedSet, whenIPhoneControls: true
        ))
        XCTAssertTrue(ATHLTHStrengthWatchControlPolicy.permits(
            .completeSet, whenIPhoneControls: true
        ))
        XCTAssertFalse(ATHLTHStrengthWatchControlPolicy.permits(
            .updateDraft, whenIPhoneControls: true
        ))
        XCTAssertFalse(ATHLTHStrengthWatchControlPolicy.permits(
            .pauseTimedSet, whenIPhoneControls: true
        ))
        XCTAssertFalse(ATHLTHStrengthWatchControlPolicy.permits(
            .resetTimedSet, whenIPhoneControls: true
        ))
        XCTAssertTrue(ATHLTHStrengthWatchControlPolicy.permits(
            .updateDraft, whenIPhoneControls: false
        ))
    }

    func testWatchNextSetCommandSurvivesEncodingAndCanBeReplayedOnce() throws {
        let command = WatchStrengthCommand(
            id: UUID(),
            workoutID: UUID(),
            kind: .skipRestAndStartTimedSet,
            reps: nil,
            weightKilograms: nil,
            restSeconds: nil,
            addRestSeconds: nil,
            sentAt: base,
            exerciseIndex: 0,
            setIndex: 1
        )
        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(WatchStrengthCommand.self, from: data)
        XCTAssertEqual(decoded.id, command.id)
        XCTAssertEqual(decoded.workoutID, command.workoutID)
        XCTAssertEqual(decoded.kind, .skipRestAndStartTimedSet)
        XCTAssertEqual(decoded.exerciseIndex, 0)
        XCTAssertEqual(decoded.setIndex, 1)
    }

    func testFiveMinuteTimerCountsDownAgainstRealClock() {
        let timer = countdown(started: base)
        XCTAssertEqual(timer.secondsRemaining(at: base), 300)
        XCTAssertEqual(timer.secondsRemaining(at: base.addingTimeInterval(120)), 180)
        XCTAssertEqual(timer.secondsRemaining(at: base.addingTimeInterval(300)), 0)
        XCTAssertTrue(timer.isFinished(at: base.addingTimeInterval(300)))
        XCTAssertEqual(timer.secondsCompleted(at: base.addingTimeInterval(400)), 300)
    }

    func testPausedCountdownDoesNotAdvanceAndResumesFromSavedRemaining() {
        var timer = countdown(started: base)
        let pauseAt = base.addingTimeInterval(125)
        timer.secondsAtPause = timer.remaining(at: pauseAt)
        timer.resumedAt = nil
        XCTAssertEqual(timer.secondsRemaining(at: base.addingTimeInterval(500)), 175)

        timer.resumedAt = base.addingTimeInterval(500)
        XCTAssertEqual(timer.secondsRemaining(at: base.addingTimeInterval(550)), 125)
        XCTAssertEqual(timer.secondsCompleted(at: base.addingTimeInterval(550)), 175)
    }

    func testTimedSetContinuesTrackingOvertimeBeyondTarget() {
        let timer = countdown(started: base)
        let elapsed = base.addingTimeInterval(425)
        XCTAssertEqual(timer.secondsRemaining(at: elapsed), 0)
        XCTAssertEqual(timer.elapsedSeconds(at: elapsed), 425)
        XCTAssertEqual(timer.overtimeSeconds(at: elapsed), 125)
        // Existing bounded progress semantics stay unchanged.
        XCTAssertEqual(timer.secondsCompleted(at: elapsed), 300)
    }

    func testPausingAndResumingOvertimeDoesNotEraseExtraTime() {
        var timer = countdown(started: base)
        let stoppedAt = base.addingTimeInterval(340)
        timer.secondsAtPause -= 340
        timer.resumedAt = nil
        XCTAssertEqual(timer.elapsedSeconds(at: stoppedAt), 340)
        XCTAssertEqual(timer.overtimeSeconds(at: stoppedAt), 40)
        timer.resumedAt = stoppedAt.addingTimeInterval(100)
        XCTAssertEqual(
            timer.elapsedSeconds(at: stoppedAt.addingTimeInterval(130)), 370
        )
        XCTAssertEqual(
            timer.overtimeSeconds(at: stoppedAt.addingTimeInterval(130)), 70
        )
    }

    func testCountdownSurvivesCheckpointRoundTripWithAbsoluteStart() throws {
        let timer = countdown(started: base)
        let restored = try JSONDecoder().decode(
            StrengthTimedSetCountdown.self,
            from: JSONEncoder().encode(timer)
        )
        XCTAssertEqual(restored.workoutID, timer.workoutID)
        XCTAssertEqual(restored.setID, timer.setID)
        XCTAssertEqual(restored.secondsRemaining(at: base.addingTimeInterval(299)), 1)
    }
}
