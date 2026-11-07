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

    func testIndependentCustomRulesSuppressBasicPeriodicTriggers() {
        var draft = AudioCoachDraft()
        draft.applySimpleAudioCoach()
        draft.customRules = [ATHLTHAudioCoachRule(
            trigger: .time, metric: .pace, interval: 30
        )]
        XCTAssertFalse(ATHLTHAudioCoachOption.distanceUpdates.isActive(in: draft))
        XCTAssertTrue(ATHLTHAudioCoachOption.customAnnouncements.isActive(in: draft))
        XCTAssertNil(draft.configuration().distanceIntervalMeters)
        ATHLTHAudioCoachOption.distanceUpdates.setActive(true, in: &draft)
        XCTAssertTrue(draft.customRules.isEmpty)
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
}
