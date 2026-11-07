import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHGuidanceStudioConfigurationTests: XCTestCase {
    func testSessionZoneAnnouncementIsIndependentOfSpokenBPM() {
        var draft = AudioCoachDraft()
        draft.enabled = true
        draft.announceHeartRate = false
        draft.smartPrompts.announceCurrentHeartRateZone = true
        draft.smartPrompts.motivationEnabled = true
        draft.smartPrompts.motivationIntervalSeconds = 60

        let configuration = draft.configuration(maximumHeartRateBPM: 188)
        XCTAssertTrue(configuration.enabled)
        XCTAssertFalse(configuration.announceHeartRate)
        XCTAssertEqual(configuration.smartPrompts?.announceCurrentHeartRateZone, true)
        XCTAssertEqual(configuration.smartPrompts?.maximumHeartRateBPM, 188)
        XCTAssertEqual(configuration.smartPrompts?.motivationIntervalSeconds, 60)
        XCTAssertNil(ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: 145, maximumBPM: nil
        ))
        XCTAssertEqual(ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: 145, maximumBPM: 188
        ), 3)
    }

    func testSavedPlannedWorkoutKeepsOtherAudioAndRecoveryFeatures() {
        var original = WatchAudioCoachConfiguration.disabled
        original.enabled = true
        original.announceHeartRate = true
        original.fuelReminderIntervalMinutes = 25
        original.fuelReminderDurationMinutes = 150
        original.fuelCarbohydrateGramsPerHour = 50
        original.preferIPhoneAudioWhenReachable = true
        original.useAcknowledgedVoiceLease = true
        original.announceStrengthSetComplete = true
        original.routeDistanceMeters = 6_500

        var draft = AudioCoachDraft()
        draft.load(configuration: original)
        XCTAssertTrue(draft.enabled)
        draft.announceHeartRate = false
        draft.smartPrompts.announceCurrentHeartRateZone = true
        draft.smartPrompts.randomEncouragementEnabled = true

        let saved = draft.applying(to: original, maximumHeartRateBPM: 181)
        XCTAssertFalse(saved.announceHeartRate)
        XCTAssertEqual(saved.smartPrompts?.announceCurrentHeartRateZone, true)
        XCTAssertEqual(saved.smartPrompts?.maximumHeartRateBPM, 181)
        XCTAssertEqual(saved.smartPrompts?.randomEncouragementEnabled, true)
        XCTAssertEqual(saved.fuelReminderIntervalMinutes, 25)
        XCTAssertEqual(saved.fuelCarbohydrateGramsPerHour, 50)
        XCTAssertEqual(saved.preferIPhoneAudioWhenReachable, true)
        XCTAssertEqual(saved.useAcknowledgedVoiceLease, true)
        XCTAssertEqual(saved.announceStrengthSetComplete, true)
        XCTAssertEqual(saved.routeDistanceMeters, 6_500)
    }

    func testGhostAudioPreferencesAreWorkoutScoped() {
        var defaults = WatchGhostRaceAudioConfiguration.disabled
        defaults.enabled = true
        defaults.distanceIntervalMeters = 1_000
        defaults.announceOvertakes = true

        var workout = GhostQuickStartDraft()
        workout.enabled = true
        workout.updatesEnabled = true
        workout.updatesConfiguration = defaults
        workout.updatesConfiguration?.distanceIntervalMeters = 500
        workout.updatesConfiguration?.announceOvertakes = false

        let saved = workout.resolvedUpdates(fallback: defaults)
        XCTAssertEqual(saved.distanceIntervalMeters, 500)
        XCTAssertEqual(saved.announceOvertakes, false)
        XCTAssertEqual(defaults.distanceIntervalMeters, 1_000)
        XCTAssertEqual(defaults.announceOvertakes, true)

        workout.updatesEnabled = false
        XCTAssertFalse(workout.resolvedUpdates(fallback: defaults).enabled)
        XCTAssertTrue(defaults.enabled)
    }

    func testLegacySmartPromptsWithoutNewZoneKeysCanStillDecode() throws {
        let oldJSON = """
        {
            "motivationEnabled": true,
            "motivationIntervalSeconds": 60,
            "randomEncouragementEnabled": false,
            "randomIntervalSeconds": 240,
            "customEncouragements": [],
            "landmarks": []
        }
        """
        let decoded = try JSONDecoder().decode(
            ATHLTHAudioCoachSmartSettings.self,
            from: Data(oldJSON.utf8)
        )
        XCTAssertTrue(decoded.motivationEnabled)
        XCTAssertNil(decoded.announceCurrentHeartRateZone)
        XCTAssertNil(decoded.maximumHeartRateBPM)
    }
 
    func testSimpleAudioCoachStartsWithHelpfulGuidance() {
        var draft = AudioCoachDraft()
        XCTAssertTrue(draft.enabled)
        XCTAssertTrue(draft.smartPrompts.motivationEnabled)
        draft.customRules = [
            ATHLTHAudioCoachRule(trigger: .distance, metric: .heartRate, interval: 500)
        ]
        draft.language = .norwegian
        draft.voiceIdentifier = "custom-voice"
        draft.speechVolume = 0.65
        draft.applySimpleAudioCoach()
        XCTAssertEqual(draft.distanceIntervalKilometers, 1.0)
        XCTAssertTrue(draft.announceDistance)
        XCTAssertTrue(draft.announceAveragePace)
        XCTAssertTrue(draft.announceWorkoutComplete)
        XCTAssertEqual(draft.customRules.count, 0)
        XCTAssertTrue(draft.smartPrompts.motivationEnabled)
        XCTAssertEqual(draft.language, .norwegian)
        XCTAssertEqual(draft.voiceIdentifier, "custom-voice")
        XCTAssertEqual(draft.speechVolume, 0.65)
        XCTAssertEqual(draft.configuration().distanceIntervalMeters, 1_000)
    }

    func testOnlyActiveOptionsAppearInAdvancedCatalogue() {
        var draft = AudioCoachDraft()
        draft.applySimpleAudioCoach()
        XCTAssertTrue(ATHLTHAudioCoachOption.distanceUpdates.isActive(in: draft))
        XCTAssertFalse(ATHLTHAudioCoachOption.timedUpdates.isActive(in: draft))
        ATHLTHAudioCoachOption.timedUpdates.setActive(true, in: &draft)
        XCTAssertTrue(ATHLTHAudioCoachOption.timedUpdates.isActive(in: draft))
        ATHLTHAudioCoachOption.timedUpdates.setActive(false, in: &draft)
        XCTAssertFalse(ATHLTHAudioCoachOption.timedUpdates.isActive(in: draft))
        ATHLTHAudioCoachOption.currentZone.setActive(true, in: &draft)
        XCTAssertTrue(draft.smartPrompts.announceCurrentHeartRateZone == true)
        ATHLTHAudioCoachOption.currentZone.setActive(false, in: &draft)
        XCTAssertFalse(ATHLTHAudioCoachOption.currentZone.isActive(in: draft))
    }

    func testCustomRulesAndBasicUpdatesRemainIndependent() {
        var draft = AudioCoachDraft()
        draft.applySimpleAudioCoach()
        draft.customRules = [ATHLTHAudioCoachRule(
            trigger: .time, metric: .heartRate, interval: 30
        )]
        XCTAssertTrue(ATHLTHAudioCoachOption.distanceUpdates.isActive(in: draft))
        XCTAssertTrue(ATHLTHAudioCoachOption.customAnnouncements.isActive(in: draft))
        XCTAssertNotNil(draft.configuration().distanceIntervalMeters)
        ATHLTHAudioCoachOption.distanceUpdates.setActive(false, in: &draft)
        XCTAssertEqual(draft.customRules.count, 1)
        XCTAssertNil(draft.configuration().distanceIntervalMeters)
        ATHLTHAudioCoachOption.distanceUpdates.setActive(true, in: &draft)
        XCTAssertEqual(draft.customRules.count, 1)
        XCTAssertNotNil(draft.configuration().distanceIntervalMeters)
    }

    func testSecondAccurateAudioUpdatesSurviveDraftRoundTrip() {
        var draft = AudioCoachDraft()
        draft.applySimpleAudioCoach()
        draft.timeTriggerEnabled = true
        draft.timeIntervalSeconds = 90
        draft.timeIntervalMinutes = 2
        let config = draft.configuration()
        XCTAssertEqual(config.timeIntervalSeconds, 90)
        var loaded = AudioCoachDraft()
        loaded.load(configuration: config)
        XCTAssertEqual(loaded.timeIntervalSeconds, 90)
        XCTAssertEqual(loaded.configuration().timeIntervalSeconds, 90)
    }

    func testTurningOnContextMotivationAlsoEnablesCoachSpeech() {
        var draft = AudioCoachDraft()
        draft.smartPrompts.motivationEnabled = false
        draft.smartPrompts.contextualFeedbackEnabled = nil
        XCTAssertFalse(ATHLTHAudioCoachOption.contextual.isActive(in: draft))
        ATHLTHAudioCoachOption.contextual.setActive(true, in: &draft)
        XCTAssertTrue(draft.smartPrompts.motivationEnabled)
        XCTAssertTrue(ATHLTHAudioCoachOption.contextual.isActive(in: draft))
        ATHLTHAudioCoachOption.contextual.setActive(false, in: &draft)
        XCTAssertFalse(ATHLTHAudioCoachOption.contextual.isActive(in: draft))
    }

    func testAdvancedZonePreferencesEncodeDecodeWithLegacyFallbacks() throws {
        var smart = ATHLTHAudioCoachSmartSettings()
        XCTAssertEqual(smart.resolvedMeasuredZoneInterval, 180)
        XCTAssertEqual(smart.resolvedAdaptiveCooldown, 150)
        smart.measuredZoneAnnouncementIntervalSeconds = 60
        smart.targetZoneVoiceAlertsEnabled = true
        smart.confirmWhenBackInZone = true
        smart.coachingMode = .custom
        smart.strongStartDurationSeconds = 180
        smart.pushOnUnexpectedPaceDrop = true
        smart.paceDropThresholdPercent = 12
        let copy = try JSONDecoder().decode(
            ATHLTHAudioCoachSmartSettings.self, from: JSONEncoder().encode(smart)
        )
        XCTAssertEqual(copy.resolvedMeasuredZoneInterval, 60)
        XCTAssertEqual(copy.coachingMode, .custom)
        XCTAssertEqual(copy.resolvedPaceDropPercent, 0.12, accuracy: 0.001)
        XCTAssertTrue(copy.pushOnUnexpectedPaceDrop == true)
    }

    func testStandardAfterAdvancedProfileDiscardsAllHiddenTriggers() {
        var draft = AudioCoachDraft()
        draft.smartPrompts.maximumHeartRateBPM = 185
        draft.smartPrompts.preferredHeartRateZone = 4
        draft.smartPrompts.measuredZoneAnnouncementIntervalSeconds = 60
        draft.smartPrompts.targetZoneVoiceAlertsEnabled = true
        draft.smartPrompts.confirmWhenBackInZone = true
        draft.smartPrompts.coachingMode = .custom
        draft.smartPrompts.strongStartDurationSeconds = 300
        draft.smartPrompts.pushWhenBelowTargetZone = true
        draft.smartPrompts.pushWhenBelowTargetPace = true
        draft.smartPrompts.pushOnUnexpectedPaceDrop = true
        draft.smartPrompts.paceDropThresholdPercent = 25
        draft.smartPrompts.adaptiveCooldownSeconds = 120
        draft.voiceIdentifier = "preferred-voice"
        draft.language = .norwegian
        draft.applySimpleAudioCoach()
        XCTAssertTrue(draft.enabled)
        XCTAssertEqual(draft.distanceIntervalKilometers, 1)
        XCTAssertNil(draft.smartPrompts.maximumHeartRateBPM)
        XCTAssertNil(draft.smartPrompts.preferredHeartRateZone)
        XCTAssertNil(draft.smartPrompts.measuredZoneAnnouncementIntervalSeconds)
        XCTAssertNil(draft.smartPrompts.targetZoneVoiceAlertsEnabled)
        XCTAssertNil(draft.smartPrompts.confirmWhenBackInZone)
        XCTAssertEqual(draft.smartPrompts.coachingMode, .automatic)
        XCTAssertNil(draft.smartPrompts.strongStartDurationSeconds)
        XCTAssertNil(draft.smartPrompts.pushWhenBelowTargetZone)
        XCTAssertNil(draft.smartPrompts.pushWhenBelowTargetPace)
        XCTAssertNil(draft.smartPrompts.pushOnUnexpectedPaceDrop)
        XCTAssertNil(draft.smartPrompts.paceDropThresholdPercent)
        XCTAssertNil(draft.smartPrompts.adaptiveCooldownSeconds)
        XCTAssertEqual(draft.voiceIdentifier, "preferred-voice")
        XCTAssertEqual(draft.language, .norwegian)
        XCTAssertNil(draft.configuration().smartPrompts?.strongStartDurationSeconds)
    }

    func testOneTapKilometerBundleCreatesOneNonDuplicatedVoiceRule() {
        var draft = AudioCoachDraft()
        draft.applySimpleAudioCoach()
        XCTAssertTrue(draft.addKilometerMetricsBundle())
        XCTAssertEqual(draft.customRules.count, 1)
        XCTAssertEqual(draft.customRules.first?.validatedInterval, 1_000)
        XCTAssertEqual(draft.customRules.first?.selectedMetrics,
                       [.distance, .elapsedTime, .heartRate])
        let config = draft.configuration()
        XCTAssertNil(config.distanceIntervalMeters)
        XCTAssertEqual(config.customRules?.count, 1)
        XCTAssertFalse(draft.addKilometerMetricsBundle())
        XCTAssertEqual(draft.customRules.count, 1)
    }

    func testKilometerBundleDoesNotResetVoiceAndRemainsSessionScoped() {
        var draft = AudioCoachDraft()
        draft.voiceIdentifier = "athlete-voice"
        draft.duckOtherAudio = false
        draft.language = .norwegian
        XCTAssertTrue(draft.addKilometerMetricsBundle())
        XCTAssertEqual(draft.voiceIdentifier, "athlete-voice")
        XCTAssertFalse(draft.duckOtherAudio)
        XCTAssertEqual(draft.configuration().language, .norwegian)
        XCTAssertTrue(draft.customRules.first?.selectedMetrics.contains(.heartRate) == true)
    }

    func testAddingCurrentZoneAnnouncementStartsWithExplicitMinuteCadence() {
        var draft = AudioCoachDraft()
        draft.applySimpleAudioCoach()
        XCTAssertNil(draft.smartPrompts.measuredZoneAnnouncementIntervalSeconds)
        ATHLTHAudioCoachOption.currentZone.setActive(true, in: &draft)
        XCTAssertEqual(draft.smartPrompts.measuredZoneAnnouncementIntervalSeconds, 60)
        XCTAssertTrue(ATHLTHAudioCoachOption.currentZone.isActive(in: draft))
        XCTAssertTrue(ATHLTHAudioCoachOption.currentZone.detail(in: draft).contains("60"))
        ATHLTHAudioCoachOption.currentZone.setActive(false, in: &draft)
        XCTAssertNil(draft.smartPrompts.measuredZoneAnnouncementIntervalSeconds)
        XCTAssertFalse(ATHLTHAudioCoachOption.currentZone.isActive(in: draft))
    }
}
