import XCTest
@testable import ATHLTH

final class AudioCoachContentLevelTests: XCTestCase {
    private func sampleConfiguration() -> WatchAudioCoachConfiguration {
        var configuration = WatchAudioCoachConfiguration.disabled
        configuration.enabled = true
        configuration.distanceIntervalMeters = 750
        configuration.timeIntervalSeconds = 420
        configuration.language = .norwegian
        configuration.voiceIdentifier = "selected-voice"
        configuration.speechRate = 0.52
        configuration.speechVolume = 0.8
        configuration.duckOtherAudio = false
        configuration.guidanceQuietPeriodSeconds = 12
        configuration.preferIPhoneAudioWhenReachable = true
        configuration.useAcknowledgedVoiceLease = true
        return configuration
    }

    func testPresetsNeverChangeCadenceOrVoiceOwner() {
        let base = sampleConfiguration()

        for level in ATHLTHCoachContentLevel.allCases {
            let updated = level.applying(to: base)
            XCTAssertTrue(updated.enabled)
            XCTAssertEqual(updated.distanceIntervalMeters, 750)
            XCTAssertEqual(updated.timeIntervalSeconds, 420)
            XCTAssertEqual(updated.language, .norwegian)
            XCTAssertEqual(updated.voiceIdentifier, "selected-voice")
            XCTAssertEqual(updated.speechRate, 0.52)
            XCTAssertEqual(updated.speechVolume, 0.8)
            XCTAssertEqual(updated.duckOtherAudio, false)
            XCTAssertEqual(updated.guidanceQuietPeriodSeconds, 12)
            XCTAssertEqual(updated.preferIPhoneAudioWhenReachable, true)
            XCTAssertEqual(updated.useAcknowledgedVoiceLease, true)
        }
    }

    func testSimpleIncludesCoreAndExcludesDenseDetails() {
        let simple = ATHLTHCoachContentLevel.simple.applying(
            to: sampleConfiguration()
        )
        XCTAssertTrue(simple.announceDistance)
        XCTAssertTrue(simple.announceElapsedTime)
        XCTAssertTrue(simple.announceCurrentWorkoutStep)
        XCTAssertFalse(simple.announceAveragePace)
        XCTAssertFalse(simple.announceHeartRate)
        XCTAssertFalse(simple.announceClockTime)
        XCTAssertFalse(simple.announceEstimatedRemainingRouteTime)
        XCTAssertTrue(simple.shouldAnnounceWorkoutStart)
        XCTAssertTrue(simple.shouldAnnouncePauseResume)
        XCTAssertTrue(simple.shouldAnnounceWorkoutComplete)
    }

    func testStandardAndAdvancedProgressivelyAddDetails() {
        let standard = ATHLTHCoachContentLevel.standard.applying(
            to: sampleConfiguration()
        )
        let advanced = ATHLTHCoachContentLevel.advanced.applying(
            to: sampleConfiguration()
        )
        XCTAssertTrue(standard.announceAveragePace)
        XCTAssertTrue(standard.announceRemainingRouteDistance)
        XCTAssertTrue(standard.announceRemainingStepTime)
        XCTAssertFalse(standard.announceHeartRate)
        XCTAssertFalse(standard.announceClockTime)

        XCTAssertTrue(advanced.announceHeartRate)
        XCTAssertTrue(advanced.announceClockTime)
        XCTAssertTrue(advanced.announceEstimatedRemainingRouteTime)
        XCTAssertTrue(advanced.announceRemainingStepDistance)
    }

    func testMatchingLevelDetectsOnlyAnExactPreset() {
        let base = sampleConfiguration()
        for level in ATHLTHCoachContentLevel.allCases {
            let preset = level.applying(to: base)
            XCTAssertEqual(
                ATHLTHCoachContentLevel.matching(preset),
                level
            )
        }
        var custom = ATHLTHCoachContentLevel.standard.applying(to: base)
        custom.announceClockTime = true
        XCTAssertNil(ATHLTHCoachContentLevel.matching(custom))
    }

    func testApplyingContentPresetNeverEnablesDisabledSession() {
        let original = WatchAudioCoachConfiguration.disabled
        for level in ATHLTHCoachContentLevel.allCases {
            XCTAssertFalse(level.applying(to: original).enabled)
            XCTAssertNil(level.applying(to: original).distanceIntervalMeters)
            XCTAssertNil(level.applying(to: original).timeIntervalSeconds)
        }
    }
}
