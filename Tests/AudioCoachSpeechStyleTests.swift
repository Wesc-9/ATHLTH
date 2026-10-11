import XCTest
@testable import ATHLTH

final class AudioCoachSpeechStyleTests: XCTestCase {
    func testBalancedDoesNotAlterOriginalSpeech() {
        let sentence = "Distance 5 kilometers. Average pace 6 minutes per kilometer."
        XCTAssertEqual(
            ATHLTHCoachSpeechStyle.balanced.render(
                sentence,
                language: .english,
                priority: .routineCoach,
                eventKind: .routineMilestone
            ),
            sentence
        )
    }

    func testMotivatingAddsOnlyPositiveNeutralProgressEncouragement() {
        let phrase = "3 av 5 sett fullført."
        let styled = ATHLTHCoachSpeechStyle.motivating.render(
            phrase,
            language: .norwegian,
            priority: .structuredStep,
            eventKind: .strengthSet
        )
        XCTAssertEqual(styled, "3 av 5 sett fullført. Bra jobbet!")
        XCTAssertEqual(
            ATHLTHCoachSpeechStyle.motivating.render(
                styled,
                language: .norwegian,
                priority: .structuredStep,
                eventKind: .strengthSet
            ),
            styled,
            "Playing the last spoken message again must not append motivation twice"
        )
    }

    func testTechnicalFramesDataWithoutChangingValues() {
        let phrase = "Distance 4 kilometers, pace 5 minutes per kilometer."
        let styled = ATHLTHCoachSpeechStyle.technical.render(
            phrase,
            language: .english,
            priority: .routineCoach,
            eventKind: .routineMilestone
        )
        XCTAssertEqual(styled, "Workout data: " + phrase)
        XCTAssertEqual(
            ATHLTHCoachSpeechStyle.technical.render(
                styled,
                language: .english,
                priority: .routineCoach,
                eventKind: .routineMilestone
            ),
            styled
        )
    }

    func testMinimalShortensUnitsWithoutLosingSensorData() {
        let phrase = "Distance 5 kilometers. Time 32 minutes. Rest 10 seconds."
        XCTAssertEqual(
            ATHLTHCoachSpeechStyle.minimal.render(
                phrase,
                language: .english,
                priority: .routineCoach,
                eventKind: .routineMilestone
            ),
            "Distance 5 km. Time 32 min. Rest 10 s."
        )
    }

    func testCriticalRouteGhostAndTargetAlertsNeverChange() {
        let original = "Stop. You are off route. 100 meters to turn."
        for style in ATHLTHCoachSpeechStyle.allCases {
            for priority in [
                ATHLTHGuidancePriority.routeCritical,
                .targetCritical, .ghostImportant, .ghostPeriodic
            ] {
                XCTAssertEqual(
                    style.render(
                        original,
                        language: .english,
                        priority: priority,
                        eventKind: .targetAlert
                    ),
                    original
                )
            }
        }
    }

    func testMotivationNeverDecoratesCountdownsOrStructuredTransitions() {
        for kind in [ATHLTHCoachEventKind.strengthRest, .runningStep] {
            XCTAssertEqual(
                ATHLTHCoachSpeechStyle.motivating.render(
                    "10 seconds remaining.",
                    language: .english,
                    priority: .structuredStep,
                    eventKind: kind
                ),
                "10 seconds remaining."
            )
        }
    }

    func testChoosingStyleDoesNotChangeThresholdsOrVoiceSettings() {
        var configuration = WatchAudioCoachConfiguration.disabled
        configuration.enabled = true
        configuration.distanceIntervalMeters = 750
        configuration.timeIntervalSeconds = 360
        configuration.speechRate = 0.57
        configuration.speechVolume = 0.7
        configuration.preferIPhoneAudioWhenReachable = true

        for style in ATHLTHCoachSpeechStyle.allCases {
            configuration.speechStyle = style
            XCTAssertEqual(configuration.distanceIntervalMeters, 750)
            XCTAssertEqual(configuration.timeIntervalSeconds, 360)
            XCTAssertEqual(configuration.speechRate, 0.57)
            XCTAssertEqual(configuration.speechVolume, 0.7)
            XCTAssertEqual(configuration.preferIPhoneAudioWhenReachable, true)
        }
    }

    func testLegacyWatchTransferWithoutStyleStillDecodes() throws {
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        config.distanceIntervalMeters = 1_000
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let decoded = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self,
            from: data
        )
        XCTAssertNil(decoded.speechStyle)
        XCTAssertEqual(decoded.distanceIntervalMeters, 1_000)

        config.speechStyle = .technical
        let encodedNew = try encoder.encode(config)
        let decodedNew = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self,
            from: encodedNew
        )
        XCTAssertEqual(decodedNew.speechStyle, .technical)
    }

    func testLegacyStrengthSettingsWithoutStyleStillDecode() throws {
        let original = StrengthAudioCoachConfiguration()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            StrengthAudioCoachConfiguration.self,
            from: data
        )
        XCTAssertNil(decoded.speechStyle)
        XCTAssertEqual(decoded.speechRate, original.speechRate)
    }
}
