import XCTest
@testable import ATHLTH

final class AudioCoachStrengthStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testNorwegianSetAndRestSummary() {
        let message = ATHLTHStrengthCoachStatusMessage.make(
            completedSets: 3,
            totalSets: 5,
            exerciseName: "Knebøy",
            restEndsAt: now.addingTimeInterval(42),
            now: now,
            norwegian: true
        )
        XCTAssertEqual(
            message,
            "3 av 5 sett fullført. Nåværende øvelse: Knebøy. 42 sekunder igjen av hvilen."
        )
    }

    func testEnglishSummaryWithoutRest() {
        let message = ATHLTHStrengthCoachStatusMessage.make(
            completedSets: 2,
            totalSets: 8,
            exerciseName: "Bench press",
            restEndsAt: nil,
            now: now,
            norwegian: false
        )
        XCTAssertEqual(
            message,
            "2 of 8 sets complete. Current exercise: Bench press."
        )
    }

    func testPastRestDeadlineIsNotAnnounced() {
        let message = ATHLTHStrengthCoachStatusMessage.make(
            completedSets: 3,
            totalSets: 4,
            exerciseName: "Roing",
            restEndsAt: now.addingTimeInterval(-15),
            now: now,
            norwegian: true
        )
        XCTAssertFalse(message.contains("hvilen"))
        XCTAssertEqual(
            message,
            "3 av 4 sett fullført. Nåværende øvelse: Roing."
        )
    }

    func testNoExerciseAndInvalidCountsRemainSafe() {
        let message = ATHLTHStrengthCoachStatusMessage.make(
            completedSets: -3,
            totalSets: -1,
            exerciseName: "  ",
            restEndsAt: nil,
            now: now,
            norwegian: false
        )
        XCTAssertEqual(message, "0 of 0 sets complete.")
    }

    func testCompletedSetsCannotExceedTotalInSpokenText() {
        let message = ATHLTHStrengthCoachStatusMessage.make(
            completedSets: 9,
            totalSets: 4,
            exerciseName: nil,
            restEndsAt: nil,
            now: now,
            norwegian: true
        )
        XCTAssertEqual(message, "9 av 9 sett fullført.")
    }

    func testVoiceOnlyPauseLeavesBothHapticAndTimersIndependent() {
        let delivery = ATHLTHCoachAlertChannels.resolve(
            delivery: .both,
            voiceEnabled: ATHLTHCoachVoicePausePolicy.allowsSpeech(
                coachEnabled: true,
                speechPaused: true,
                priority: .structuredStep
            ),
            hapticsEnabled: true,
            hapticPermittedByPriority: true
        )
        XCTAssertFalse(delivery.voice)
        XCTAssertTrue(delivery.haptic)
    }
}
