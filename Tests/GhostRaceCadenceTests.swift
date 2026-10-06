import Foundation
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

    @MainActor
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
        XCTAssertEqual(
            configuration
                .resolvedStatusDetailMode,
            .both
        )
        XCTAssertTrue(
            configuration
                .shouldAnnounceOvertakes
        )
        XCTAssertTrue(
            configuration
                .shouldAnnounceFinalPhase
        )
        XCTAssertEqual(
            configuration
                .resolvedFinalPhaseStartMeters,
            500
        )
        XCTAssertTrue(
            configuration
                .shouldAnnounceLiveConnectionChanges
        )
    }

    @MainActor
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

    @MainActor
    func testGhostStatusModePersistsAndTransfers() {
        let defaults =
            makeDefaults()
        let settings =
            AppSettingsStore(
                defaults: defaults
            )

        settings
            .ghostRaceStatusDetailMode =
            .time
        settings
            .ghostRaceAnnounceOvertakes =
            false
        settings
            .ghostRaceFinalPhaseEnabled =
            true
        settings
            .ghostRaceFinalPhaseStartMeters =
            1_000
        settings
            .ghostRaceLiveConnectionAlerts =
            false

        let configuration =
            settings
                .ghostRaceAudioConfiguration

        XCTAssertEqual(
            configuration
                .resolvedStatusDetailMode,
            .time
        )
        XCTAssertFalse(
            configuration
                .shouldAnnounceOvertakes
        )
        XCTAssertTrue(
            configuration
                .shouldAnnounceFinalPhase
        )
        XCTAssertEqual(
            configuration
                .resolvedFinalPhaseStartMeters,
            1_000
        )
        XCTAssertFalse(
            configuration
                .shouldAnnounceLiveConnectionChanges
        )
    }

    func testFriendGhostIdentityIsOptionalAndPreserved() throws {
        let transfer =
            WatchGhostRaceTransfer(
                title: "Reference",
                referenceDuration: 1_800,
                routeDistanceMeters: 5_000,
                points: [],
                audio: .standard,
                opponentName: "Runner"
            )

        let encoded =
            try JSONEncoder()
                .encode(transfer)
        let decoded =
            try JSONDecoder()
                .decode(
                    WatchGhostRaceTransfer.self,
                    from: encoded
                )

        XCTAssertEqual(
            decoded.opponentName,
            "Runner"
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
