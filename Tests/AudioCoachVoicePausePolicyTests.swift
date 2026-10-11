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
                speechPaused: false,
            priority: .routineCoach
            )
        )
        XCTAssertFalse(
            ATHLTHCoachVoicePausePolicy.allowsSpeech(
                coachEnabled: coach.enabled,
                speechPaused: true,
            priority: .routineCoach
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
                speechPaused: false,
            priority: .routineCoach
            )
        )
        XCTAssertFalse(
            ATHLTHCoachVoicePausePolicy.allowsSpeech(
                coachEnabled: false,
                speechPaused: true,
            priority: .routineCoach
            )
        )
    }

    func testMutedVoiceDoesNotSuppressSelectedSafetyHaptics() {
        let channels = ATHLTHCoachAlertChannels.resolve(
            delivery: .both,
            voiceEnabled: ATHLTHCoachVoicePausePolicy.allowsSpeech(
                coachEnabled: true,
                speechPaused: true,
            priority: .routineCoach
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
                speechPaused: paused,
            priority: .routineCoach
            )
        )
        paused = false
        XCTAssertTrue(
            ATHLTHCoachVoicePausePolicy.allowsSpeech(
                coachEnabled: configured.enabled,
                speechPaused: paused,
            priority: .routineCoach
            )
        )
        XCTAssertEqual(configured.distanceIntervalMeters, 500)
        XCTAssertEqual(configured.timeIntervalSeconds, 300)
    }
    func testIndependentCriticalAndGhostAlertsRemainAllowedDuringCoachMute() {
        for priority: ATHLTHGuidancePriority in [
            .routeCritical, .targetCritical, .ghostPeriodic, .ghostImportant
        ] {
            XCTAssertTrue(
                ATHLTHCoachVoicePausePolicy.allowsSpeech(
                    coachEnabled: false,
                    speechPaused: true,
                    priority: priority
                )
            )
        }
    }

    func testStructuredAudioCoachRespectsMute() {
        XCTAssertFalse(
            ATHLTHCoachVoicePausePolicy.allowsSpeech(
                coachEnabled: true,
                speechPaused: true,
                priority: .structuredStep
            )
        )
    }

}
