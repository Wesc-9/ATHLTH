import XCTest
@testable import ATHLTH

final class AudioCoachVoicePausePolicyTests: XCTestCase {
    func testManualMuteBlocksSpeechButDoesNotRewriteCoachConfiguration() {
        var coach = WatchAudioCoachConfiguration.disabled
        coach.enabled = true
        coach.distanceIntervalMeters = 1_000
        coach.timeIntervalSeconds = 600

        XCTAssertTrue(
            ATHLTHCoachVoicePausePolicy.allowsSpeech(
                coachEnabled: coach.enabled,
                speechPaused: false
            )
        )
        XCTAssertFalse(
            ATHLTHCoachVoicePausePolicy.allowsSpeech(
                coachEnabled: coach.enabled,
                speechPaused: true
            )
        )
        XCTAssertEqual(coach.distanceIntervalMeters, 1_000)
        XCTAssertEqual(coach.timeIntervalSeconds, 600)
        XCTAssertTrue(coach.enabled)
    }

    func testDisabledCoachCannotSpeakWhenResumeVoiceIsTapped() {
        XCTAssertFalse(
            ATHLTHCoachVoicePausePolicy.allowsSpeech(
                coachEnabled: false,
                speechPaused: false
            )
        )
        XCTAssertFalse(
            ATHLTHCoachVoicePausePolicy.allowsSpeech(
                coachEnabled: false,
                speechPaused: true
            )
        )
    }

    func testMutedVoiceDoesNotSuppressSelectedSafetyHaptics() {
        let channels = ATHLTHCoachAlertChannels.resolve(
            delivery: .both,
            voiceEnabled: ATHLTHCoachVoicePausePolicy.allowsSpeech(
                coachEnabled: true,
                speechPaused: true
            ),
            hapticsEnabled: true,
            hapticPermittedByPriority: true
        )
        XCTAssertFalse(channels.voice)
        XCTAssertTrue(channels.haptic)
    }

    func testSpeechCanResumeWithoutReconfiguringMilestones() {
        let original = WatchAudioCoachConfiguration.disabled
        var configured = original
        configured.enabled = true
        configured.distanceIntervalMeters = 500
        configured.timeIntervalSeconds = 300

        var paused = true
        XCTAssertFalse(
            ATHLTHCoachVoicePausePolicy.allowsSpeech(
                coachEnabled: configured.enabled,
                speechPaused: paused
            )
        )
        paused = false
        XCTAssertTrue(
            ATHLTHCoachVoicePausePolicy.allowsSpeech(
                coachEnabled: configured.enabled,
                speechPaused: paused
            )
        )
        XCTAssertEqual(configured.distanceIntervalMeters, 500)
        XCTAssertEqual(configured.timeIntervalSeconds, 300)
    }
}
