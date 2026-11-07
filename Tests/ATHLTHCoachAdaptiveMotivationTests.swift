import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHCoachAdaptiveMotivationTests: XCTestCase {
    func testStartPushHasCooldownAndStopsAfterConfiguredWindow() {
        var settings = ATHLTHAudioCoachSmartSettings()
        settings.coachingMode = .custom
        settings.strongStartDurationSeconds = 180
        settings.adaptiveCooldownSeconds = 60
        var state = ATHLTHCoachAdaptiveMotivation()
        func cue(_ second: Double) -> String? {
            state.nextCue(
                settings: settings, elapsed: second,
                measuredPaceSecondsPerKilometer: nil,
                targetSlowestPaceSecondsPerKilometer: nil,
                measuredHeartRateBPM: nil, targetHeartRateMinimumBPM: nil,
                reliableNotClimbing: false, norwegian: true
            )
        }
        XCTAssertNotNil(cue(25))
        XCTAssertNil(cue(55))
        XCTAssertNotNil(cue(95))
        XCTAssertNil(cue(110))
        XCTAssertNil(cue(270))
    }

    func testLowHeartRateRequiresStableValidTarget() {
        var settings = ATHLTHAudioCoachSmartSettings()
        settings.coachingMode = .custom
        settings.pushWhenBelowTargetZone = true
        var state = ATHLTHCoachAdaptiveMotivation()
        func cue(_ second: Double, bpm: Double?, minBPM: Double?) -> String? {
            state.nextCue(
                settings: settings, elapsed: second,
                measuredPaceSecondsPerKilometer: nil,
                targetSlowestPaceSecondsPerKilometer: nil,
                measuredHeartRateBPM: bpm, targetHeartRateMinimumBPM: minBPM,
                reliableNotClimbing: false, norwegian: true
            )
        }
        XCTAssertNil(cue(100, bpm: 135, minBPM: nil))
        XCTAssertNil(cue(120, bpm: 140, minBPM: 145))
        XCTAssertNil(cue(132, bpm: 140, minBPM: 145))
        XCTAssertNotNil(cue(139, bpm: 140, minBPM: 145))
        XCTAssertNil(cue(150, bpm: 140, minBPM: 145))
        XCTAssertNil(cue(165, bpm: nil, minBPM: 145))
    }

    func testPaceDropDoesNotFireWhenUphillOrUnknown() {
        var settings = ATHLTHAudioCoachSmartSettings()
        settings.coachingMode = .custom
        settings.pushOnUnexpectedPaceDrop = true
        settings.paceDropThresholdPercent = 12
        var state = ATHLTHCoachAdaptiveMotivation()
        func cue(_ second: Double, pace: Double, verifiedNotClimbing: Bool) -> String? {
            state.nextCue(
                settings: settings, elapsed: second,
                measuredPaceSecondsPerKilometer: pace,
                targetSlowestPaceSecondsPerKilometer: nil,
                measuredHeartRateBPM: nil, targetHeartRateMinimumBPM: nil,
                reliableNotClimbing: verifiedNotClimbing, norwegian: true
            )
        }
        XCTAssertNil(cue(90, pace: 330, verifiedNotClimbing: true))
        XCTAssertNil(cue(100, pace: 390, verifiedNotClimbing: false))
        XCTAssertNil(cue(110, pace: 390, verifiedNotClimbing: true))
        XCTAssertNil(cue(125, pace: 390, verifiedNotClimbing: true))
        XCTAssertNotNil(cue(140, pace: 390, verifiedNotClimbing: true))
    }

    func testCustomPreferencesSurviveProfileEncoding() throws {
        var smart = ATHLTHAudioCoachSmartSettings()
        smart.coachingMode = .custom
        smart.strongStartDurationSeconds = 120
        smart.pushWhenBelowTargetZone = true
        smart.pushWhenBelowTargetPace = true
        smart.pushOnUnexpectedPaceDrop = true
        smart.paceDropThresholdPercent = 12
        smart.adaptiveCooldownSeconds = 120
        smart.measuredZoneAnnouncementIntervalSeconds = 60
        smart.preferredHeartRateZone = 3
        smart.targetZoneVoiceAlertsEnabled = true
        smart.confirmWhenBackInZone = true

        let decoded = try JSONDecoder().decode(
            ATHLTHAudioCoachSmartSettings.self,
            from: JSONEncoder().encode(smart)
        )
        XCTAssertEqual(decoded.coachingMode, .custom)
        XCTAssertEqual(decoded.strongStartDurationSeconds, 120)
        XCTAssertTrue(decoded.pushWhenBelowTargetZone == true)
        XCTAssertTrue(decoded.pushWhenBelowTargetPace == true)
        XCTAssertTrue(decoded.pushOnUnexpectedPaceDrop == true)
        XCTAssertEqual(decoded.resolvedPaceDropPercent, 0.12, accuracy: 0.0001)
        XCTAssertEqual(decoded.resolvedMeasuredZoneInterval, 60)
        XCTAssertEqual(decoded.preferredHeartRateZone, 3)
        XCTAssertTrue(decoded.confirmWhenBackInZone == true)
    }

    func testRepeatedZonePushHasItsOwnCooldownAndVariedPhrase() {
        var settings = ATHLTHAudioCoachSmartSettings()
        settings.coachingMode = .custom
        settings.pushWhenBelowTargetZone = true
        settings.adaptiveCooldownSeconds = 60
        settings.belowZoneRepeatSeconds = 180
        settings.encouragementStyle = .push
        var state = ATHLTHCoachAdaptiveMotivation()
        func cue(_ t: Double) -> String? {
            state.nextCue(
                settings: settings, elapsed: t,
                measuredPaceSecondsPerKilometer: nil,
                targetSlowestPaceSecondsPerKilometer: nil,
                measuredHeartRateBPM: 125,
                targetHeartRateMinimumBPM: 145,
                reliableNotClimbing: false, norwegian: true
            )
        }
        XCTAssertNil(cue(100))
        let first = cue(122)
        XCTAssertNotNil(first)
        XCTAssertNil(cue(190))
        let second = cue(305)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first, second)
    }
}
