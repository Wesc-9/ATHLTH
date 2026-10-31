import XCTest
@testable import ATHLTH

final class ATHLTHHeartRateZoneCoachTargetTests: XCTestCase {
    private var oldConfiguration: WatchWorkoutTargetAlertConfiguration {
        WatchWorkoutTargetAlertConfiguration(
            heartRateEnabled: true,
            heartRateZone: 2,
            heartRateMinimumBPM: 114,
            heartRateMaximumBPM: 133,
            paceAlertsEnabled: true,
            paceToleranceSecondsPerKilometer: 20,
            graceSeconds: 15,
            repeatSeconds: 180,
            delivery: .haptic,
            announceBackInTarget: true
        )
    }

    func testStepTargetOverridesGlobalZoneWithoutLosingDebounce() {
        let target = ATHLTHHeartRateZoneCoachTarget.configuration(
            configured: oldConfiguration,
            stepZone: 4,
            maximumBPM: 190
        )
        XCTAssertEqual(target?.heartRateZone, 4)
        XCTAssertEqual(target?.heartRateMinimumBPM, 152)
        XCTAssertEqual(target?.heartRateMaximumBPM, 171)
        XCTAssertEqual(target?.graceSeconds, 15)
        XCTAssertEqual(target?.repeatSeconds, 180)
        XCTAssertTrue(target?.paceAlertsEnabled == true)
    }

    func testZoneTargetWorksWithoutSeparateAlertConfiguration() {
        let target = ATHLTHHeartRateZoneCoachTarget.configuration(
            configured: nil, stepZone: 3, maximumBPM: 200
        )
        XCTAssertTrue(target?.heartRateEnabled == true)
        XCTAssertEqual(target?.heartRateMinimumBPM, 140)
        XCTAssertEqual(target?.heartRateMaximumBPM, 160)
        XCTAssertEqual(target?.graceSeconds, 10)
        XCTAssertEqual(target?.repeatSeconds, 120)
    }

    func testMissingMaximumDoesNotInventPulseThresholds() {
        XCTAssertNil(ATHLTHHeartRateZoneCoachTarget.configuration(
            configured: nil, stepZone: 4, maximumBPM: nil
        ))
        XCTAssertNil(ATHLTHHeartRateZoneCoachTarget.configuration(
            configured: nil, stepZone: 9, maximumBPM: 190
        ))
    }

    func testNeverReplacesExplicitBpmTargetWhenNoZoneSelected() {
        let target = ATHLTHHeartRateZoneCoachTarget.configuration(
            configured: oldConfiguration, stepZone: nil, maximumBPM: 190
        )
        XCTAssertEqual(target, oldConfiguration)
    }

    func testHapticAlertsGainVoiceOnlyWhenAudioCoachEnabled() {
        XCTAssertEqual(ATHLTHHeartRateZoneCoachTarget.spokenDelivery(
            .haptic, coachEnabled: true), .both)
        XCTAssertEqual(ATHLTHHeartRateZoneCoachTarget.spokenDelivery(
            .haptic, coachEnabled: false), .haptic)
        XCTAssertEqual(ATHLTHHeartRateZoneCoachTarget.spokenDelivery(
            .voice, coachEnabled: true), .voice)
    }
}
