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
}
