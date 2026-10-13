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

    func testExperiencePresetsHavePredictableContentAndCadence() {
        let calm = ATHLTHCoachExperiencePreset.calm
        let balanced = ATHLTHCoachExperiencePreset.balanced
        let active = ATHLTHCoachExperiencePreset.active

        XCTAssertEqual(ATHLTHCoachExperiencePreset.allCases.count, 3)
        XCTAssertEqual(calm.contentLevel, .simple)
        XCTAssertEqual(balanced.contentLevel, .standard)
        XCTAssertEqual(active.contentLevel, .advanced)
        XCTAssertEqual(calm.speechStyle, .minimal)
        XCTAssertEqual(balanced.speechStyle, .balanced)
        XCTAssertEqual(active.speechStyle, .motivating)
        XCTAssertEqual(calm.distanceIntervalKilometers, 2.0)
        XCTAssertEqual(balanced.distanceIntervalKilometers, 1.0)
        XCTAssertEqual(active.distanceIntervalKilometers, 0.5)
    }

    func testRunningExperiencePreservesVoiceAndAppliesFrequency() {
        for preset in ATHLTHCoachExperiencePreset.allCases {
            var draft = AudioCoachDraft()
            draft.language = .norwegian
            draft.voiceIdentifier = "my-favorite-voice"
            draft.speechRate = 0.55
            draft.speechVolume = 0.7
            draft.duckOtherAudio = false
            draft.timeTriggerEnabled = true

            draft.applyExperience(preset)

            XCTAssertTrue(draft.enabled)
            XCTAssertTrue(draft.distanceTriggerEnabled)
            XCTAssertFalse(draft.timeTriggerEnabled)
            XCTAssertEqual(
                draft.distanceIntervalKilometers,
                preset.distanceIntervalKilometers
            )
            XCTAssertEqual(draft.experiencePreset, preset)
            XCTAssertEqual(draft.speechStyle, preset.speechStyle)
            XCTAssertEqual(draft.voiceIdentifier, "my-favorite-voice")
            XCTAssertEqual(draft.language, .norwegian)
            XCTAssertEqual(draft.speechRate, 0.55)
            XCTAssertEqual(draft.speechVolume, 0.7)
            XCTAssertFalse(draft.duckOtherAudio)
        }
    }


    func testWatchExperiencePresetsPreserveDeliveryAndUseSportSpecificCues() {
        var original = WatchAudioCoachConfiguration.disabled
        original.language = .norwegian
        original.voiceIdentifier = "chosen-voice"
        original.speechRate = 0.55
        original.speechVolume = 0.7
        original.duckOtherAudio = false
        original.preferIPhoneAudioWhenReachable = true
        original.useAcknowledgedVoiceLease = true

        for preset in ATHLTHCoachExperiencePreset.allCases {
            for kind in [WatchWorkoutKind.running, .walking, .strength, .hiit] {
                let updated = preset.applying(to: original, kind: kind)
                XCTAssertTrue(updated.enabled)
                XCTAssertTrue(preset.matches(updated, kind: kind))
                XCTAssertEqual(updated.language, .norwegian)
                XCTAssertEqual(updated.voiceIdentifier, "chosen-voice")
                XCTAssertEqual(updated.speechRate, 0.55)
                XCTAssertEqual(updated.speechVolume, 0.7)
                XCTAssertEqual(updated.duckOtherAudio, false)
                XCTAssertEqual(updated.preferIPhoneAudioWhenReachable, true)
                XCTAssertEqual(updated.useAcknowledgedVoiceLease, true)

                if kind == .running || kind == .walking {
                    XCTAssertEqual(
                        updated.distanceIntervalMeters,
                        preset.distanceIntervalKilometers * 1_000
                    )
                    XCTAssertNil(updated.timeIntervalSeconds)
                } else if kind == .strength {
                    XCTAssertNil(updated.distanceIntervalMeters)
                    XCTAssertEqual(updated.announceStrengthNextExercise, true)
                    XCTAssertEqual(
                        updated.shouldAnnounceStrengthRestCountdown,
                        preset != .calm
                    )
                } else {
                    XCTAssertNil(updated.distanceIntervalMeters)
                    XCTAssertNotNil(updated.timeIntervalSeconds)
                }
            }
        }
    }


    func testRoutineCoachDefersToStructuredStepTransitions() {
        let timed = WatchRunningWorkoutStep(
            id: UUID(),
            title: "Interval",
            measure: .time,
            distanceMeters: nil,
            durationSeconds: 60,
            intensityText: nil
        )
        XCTAssertTrue(ATHLTHCoachRoutineContextPolicy.shouldSpeakMilestone(
            step: nil, elapsedInStep: 1, distanceInStepMeters: 0))
        XCTAssertFalse(ATHLTHCoachRoutineContextPolicy.shouldSpeakMilestone(
            step: timed, elapsedInStep: 8, distanceInStepMeters: 0))
        XCTAssertTrue(ATHLTHCoachRoutineContextPolicy.shouldSpeakMilestone(
            step: timed, elapsedInStep: 30, distanceInStepMeters: 0))
        XCTAssertFalse(ATHLTHCoachRoutineContextPolicy.shouldSpeakMilestone(
            step: timed, elapsedInStep: 49, distanceInStepMeters: 0))

        let distance = WatchRunningWorkoutStep(
            id: UUID(),
            title: "Run",
            measure: .distance,
            distanceMeters: 1_000,
            durationSeconds: nil,
            intensityText: nil
        )
        XCTAssertTrue(ATHLTHCoachRoutineContextPolicy.shouldSpeakMilestone(
            step: distance, elapsedInStep: 180, distanceInStepMeters: 700))
        XCTAssertFalse(ATHLTHCoachRoutineContextPolicy.shouldSpeakMilestone(
            step: distance, elapsedInStep: 240, distanceInStepMeters: 960))
    }

    func testPlannedStepSpeechUsesRealTargetAndLocalization() {
        var step = WatchRunningWorkoutStep(
            id: UUID(),
            title: "Drag",
            measure: .time,
            distanceMeters: nil,
            durationSeconds: 90,
            intensityText: nil
        )
        step.targetPaceMinSecondsPerKilometer = 300
        step.targetPaceMaxSecondsPerKilometer = 330
        let norwegian = ATHLTHCoachStructuredStepSpeech.phrase(
            for: step, position: .next, norwegian: true
        )
        XCTAssertTrue(norwegian.contains("Neste"))
        XCTAssertTrue(norwegian.contains("1 minutt 30 sekunder"))
        XCTAssertTrue(norwegian.contains("Målfart 5:00–5:30 min/km"))
        let english = ATHLTHCoachStructuredStepSpeech.phrase(
            for: step, position: .starting, norwegian: false
        )
        XCTAssertTrue(english.contains("Starting"))
        XCTAssertTrue(english.contains("Target pace 5:00–5:30"))
    }


    func testStructuredStepRemainingSummaryOnlyAnnouncesExplicitTargets() {
        let step = WatchRunningWorkoutStep(
            id: UUID(), title: "Drag",
            measure: .time, distanceMeters: nil,
            durationSeconds: 90, intensityText: nil
        )
        XCTAssertEqual(
            ATHLTHCoachStructuredStepSpeech.remainingSummary(
                for: step,
                elapsedInStep: 45,
                distanceInStepMeters: 0,
                announceTime: true,
                announceDistance: false,
                norwegian: true
            ),
            "Tid igjen i intervallet: 45 sekunder"
        )
        XCTAssertNil(
            ATHLTHCoachStructuredStepSpeech.remainingSummary(
                for: step,
                elapsedInStep: 45,
                distanceInStepMeters: 0,
                announceTime: false,
                announceDistance: true,
                norwegian: true
            )
        )
        XCTAssertNil(
            ATHLTHCoachStructuredStepSpeech.remainingSummary(
                for: step,
                elapsedInStep: 90,
                distanceInStepMeters: 0,
                announceTime: true,
                announceDistance: true,
                norwegian: true
            )
        )
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
