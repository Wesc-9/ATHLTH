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

    func testMissingMaximumNeverUsesAnotherIntervalsOldZone() {
        let target = ATHLTHHeartRateZoneCoachTarget.configuration(
            configured: oldConfiguration, stepZone: 4, maximumBPM: nil
        )
        XCTAssertEqual(target?.heartRateEnabled, false)
        XCTAssertNil(target?.heartRateZone)
        XCTAssertTrue(target?.paceAlertsEnabled == true)
    }

    func testNeverReplacesExplicitBpmTargetWhenNoZoneSelected() {
        let target = ATHLTHHeartRateZoneCoachTarget.configuration(
            configured: oldConfiguration, stepZone: nil, maximumBPM: 190
        )
        XCTAssertEqual(target, oldConfiguration)
    }

    func testUnzonedRecoveryNeverInheritsPreviousZ5Target() {
        let previous = oldConfiguration
        let recovery = ATHLTHHeartRateZoneCoachTarget.configuration(
            configured: previous,
            stepZone: nil,
            maximumBPM: 190,
            suppressHeartRateForUnzonedStep: true
        )
        XCTAssertFalse(recovery?.heartRateEnabled ?? true)
        XCTAssertNil(recovery?.heartRateZone)
        XCTAssertNil(recovery?.heartRateMinimumBPM)
        XCTAssertNil(recovery?.heartRateMaximumBPM)
        XCTAssertTrue(recovery?.paceAlertsEnabled == true)
        XCTAssertEqual(recovery?.repeatSeconds, previous.repeatSeconds)
        // Never mutate the original workout-wide setting.
        XCTAssertTrue(previous.heartRateEnabled)
    }

    func testMultiZoneHeartRateTargetKeepsFullPercentBand() {
        let target = ATHLTHHeartRateZoneCoachTarget.configuration(
            configured: oldConfiguration,
            stepZone: nil,
            maximumBPM: 190,
            stepPercentMin: 50,
            stepPercentMax: 70
        )
        XCTAssertTrue(target?.heartRateEnabled == true)
        XCTAssertNil(target?.heartRateZone)
        XCTAssertEqual(target?.heartRateMinimumBPM, 95)
        XCTAssertEqual(target?.heartRateMaximumBPM, 133)
        XCTAssertTrue(target?.paceAlertsEnabled == true)
        XCTAssertEqual(target?.graceSeconds, 15)
        XCTAssertEqual(target?.repeatSeconds, 180)
    }

    func testMultiZoneTargetWithoutMaximumNeverInheritsGlobalZone() {
        let target = ATHLTHHeartRateZoneCoachTarget.configuration(
            configured: oldConfiguration,
            stepZone: nil, maximumBPM: nil,
            stepPercentMin: 50, stepPercentMax: 70
        )
        XCTAssertEqual(target?.heartRateEnabled, false)
        XCTAssertNil(target?.heartRateZone)
        XCTAssertNil(target?.heartRateMinimumBPM)
        XCTAssertNil(target?.heartRateMaximumBPM)
        XCTAssertTrue(target?.paceAlertsEnabled == true)
    }

    func testSingleZoneSourcePercentOverridesOlderConfiguredZone() {
        let target = ATHLTHHeartRateZoneCoachTarget.configuration(
            configured: oldConfiguration,
            stepZone: 5, maximumBPM: 190,
            stepPercentMin: 90, stepPercentMax: 100
        )
        XCTAssertEqual(target?.heartRateZone, 5)
        XCTAssertEqual(target?.heartRateMinimumBPM, 171)
        XCTAssertEqual(target?.heartRateMaximumBPM, 190)
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
