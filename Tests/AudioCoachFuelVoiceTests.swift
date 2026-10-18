import XCTest
@testable import ATHLTH

final class AudioCoachFuelVoiceTests: XCTestCase {
    private func voiceConfiguration(
        language: WatchAudioCoachLanguage = .norwegian
    ) -> WatchAudioCoachConfiguration {
        var config = WatchAudioCoachConfiguration.disabled
        config.enabled = true
        config.language = language
        config.fuelReminderIntervalMinutes = 20
        config.fuelReminderDurationMinutes = 120
        config.fuelCarbohydrateGramsPerHour = 45
        config.fuelFluidMLPerHour = 600
        return config
    }

    func testVoiceRemindersRequireEnabledCoachAndValidPlan() {
        var config = voiceConfiguration()
        XCTAssertEqual(config.resolvedFuelIntervalSeconds, 1_200)
        config.enabled = false
        XCTAssertNil(config.resolvedFuelIntervalSeconds)
        config.enabled = true
        config.fuelCarbohydrateGramsPerHour = 0
        config.fuelFluidMLPerHour = 0
        XCTAssertNil(config.resolvedFuelIntervalSeconds)
        config.fuelFluidMLPerHour = 500
        XCTAssertNotNil(config.resolvedFuelIntervalSeconds)
        config.fuelReminderIntervalMinutes = 0
        XCTAssertNil(config.resolvedFuelIntervalSeconds)
    }

    func testVoiceRemindersUseWorkoutElapsedTimeAndStopAtDuration() {
        let config = voiceConfiguration()
        XCTAssertEqual(
            ATHLTHFuelVoicePrompt.nextDue(after: 0, config: config), 1_200
        )
        XCTAssertEqual(
            ATHLTHFuelVoicePrompt.nextDue(after: 1_200, config: config), 2_400
        )
        XCTAssertEqual(
            ATHLTHFuelVoicePrompt.nextDue(after: 5_999, config: config), 6_000
        )
        XCTAssertNil(
            ATHLTHFuelVoicePrompt.nextDue(after: 6_000, config: config)
        )
        XCTAssertNil(
            ATHLTHFuelVoicePrompt.nextDue(after: .nan, config: config)
        )
    }

    func testPauseOrReconnectDoesNotSpeakStaleNutritionCue() {
        XCTAssertTrue(
            ATHLTHFuelVoicePrompt.isFreshDue(
                elapsed: 1_201, scheduled: 1_200
            )
        )
        XCTAssertFalse(
            ATHLTHFuelVoicePrompt.isFreshDue(
                elapsed: 1_230, scheduled: 1_200
            )
        )
        XCTAssertFalse(
            ATHLTHFuelVoicePrompt.isFreshDue(
                elapsed: 1_199, scheduled: 1_200
            )
        )
    }

    func testNorwegianAndEnglishVoiceAmountsMatchPlan() {
        let norwegian = ATHLTHFuelVoicePrompt.phrase(
            config: voiceConfiguration()
        )
        XCTAssertTrue(norwegian?.contains("200 milliliter") == true)
        XCTAssertTrue(norwegian?.contains("15 gram") == true)

        let english = ATHLTHFuelVoicePrompt.phrase(
            config: voiceConfiguration(language: .english)
        )
        XCTAssertTrue(english?.contains("200 milliliters") == true)
        XCTAssertTrue(english?.contains("15 grams") == true)
    }

    func testFuelVoiceConfigSurvivesWatchTransferRoundTrip() throws {
        let config = voiceConfiguration()
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(
            WatchAudioCoachConfiguration.self, from: data
        )
        XCTAssertEqual(decoded.fuelReminderIntervalMinutes, 20)
        XCTAssertEqual(decoded.fuelReminderDurationMinutes, 120)
        XCTAssertEqual(decoded.fuelCarbohydrateGramsPerHour, 45)
        XCTAssertEqual(decoded.fuelFluidMLPerHour, 600)

        let legacy = WatchAudioCoachConfiguration.disabled
        XCTAssertNil(legacy.resolvedFuelIntervalSeconds)
    }

    func testWatchOrPhoneOwnsRoutineSpeechButNeverBoth() {
        var config = voiceConfiguration()
        config.preferIPhoneAudioWhenReachable = true

        XCTAssertFalse(ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
            configuration: config,
            workoutKind: .running,
            priority: .routineCoach,
            iPhoneVoiceLeaseActive: true
        ))
        XCTAssertTrue(ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
            configuration: config,
            workoutKind: .running,
            priority: .routineCoach,
            iPhoneVoiceLeaseActive: false
        ))
    }
}
