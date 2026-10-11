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
