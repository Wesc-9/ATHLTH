import XCTest
@testable import ATHLTH

final class GhostRaceCadenceTests:
    XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite =
            "GhostRaceCadenceTests." +
            UUID().uuidString
        let defaults =
            UserDefaults(
                suiteName: suite
            )!
        defaults.removePersistentDomain(
            forName: suite
        )
        return defaults
    }

    func testDefaultGhostCadenceIsOneKilometreWithoutExtraLeadAlerts() {
        let settings =
            AppSettingsStore(
                defaults: makeDefaults()
            )
        let configuration =
            settings
                .ghostRaceAudioConfiguration

        XCTAssertEqual(
            configuration
                .distanceIntervalMeters,
            1_000
        )
        XCTAssertNil(
            configuration
                .timeIntervalSeconds
        )
        XCTAssertFalse(
            configuration
                .announceLeadChanges
        )
    }

    func testGhostDistanceAndTimeUnitsAreConvertedExactly() {
        let settings =
            AppSettingsStore(
                defaults: makeDefaults()
            )

        settings
            .ghostRaceAudioUseDistance =
            true
        settings
            .ghostRaceAudioDistanceIntervalKilometers =
            1.0
        settings
            .ghostRaceAudioUseTime =
            true
        settings
            .ghostRaceAudioTimeIntervalMinutes =
            5

        let configuration =
            settings
                .ghostRaceAudioConfiguration

        XCTAssertEqual(
            configuration
                .distanceIntervalMeters,
            1_000
        )
        XCTAssertEqual(
            configuration
                .timeIntervalSeconds,
            300
        )
    }

    func testLeadChangeEventsAreSlowerThanPeriodicCadence() {
        let configuration =
            WatchGhostRaceAudioConfiguration
                .standard

        XCTAssertEqual(
            configuration
                .resolvedLeadChangeCooldownSeconds,
            90
        )
        XCTAssertEqual(
            configuration
                .resolvedImportantLeadChangeCooldownSeconds,
            60
        )
        XCTAssertGreaterThanOrEqual(
            configuration
                .resolvedLeadFlipThresholdMeters,
            20
        )
    }
}
