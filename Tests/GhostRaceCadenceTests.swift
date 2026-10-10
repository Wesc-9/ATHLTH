import Foundation
import XCTest
@testable import ATHLTH

@MainActor
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

    func testTargetPaceAndFinishTimeConversion() {
        XCTAssertEqual(
            GhostTargetPaceFormatter.secondsPerKilometer(from: "4:45"), 285
        )
        XCTAssertNil(
            GhostTargetPaceFormatter.secondsPerKilometer(from: "4:80")
        )
        XCTAssertNil(
            GhostTargetPaceFormatter.secondsPerKilometer(from: "0:30")
        )
        XCTAssertEqual(
            GhostTargetPaceFormatter.text(secondsPerKilometer: 285), "4:45"
        )
        XCTAssertEqual(
            GhostTargetPaceFormatter.duration(
                paceSeconds: 285, routeKilometers: 12.4
            ), 3534
        )
        XCTAssertEqual(GhostTargetTimeFormatter.string(3534), "58:54")
    }

    func testAllTargetStrategiesKeepFinishAndMonotonicProgress() {
        for strategy in GhostTargetPacingStrategy.allCases {
            XCTAssertEqual(strategy.elapsedFraction(at: 0), 0, accuracy: 0.0001)
            XCTAssertEqual(strategy.elapsedFraction(at: 1), 1, accuracy: 0.0001)
            var previous = 0.0
            for step in 1...100 {
                let fraction = strategy.elapsedFraction(
                    at: Double(step) / 100
                )
                XCTAssertGreaterThan(fraction, previous)
                previous = fraction
            }
        }
        XCTAssertEqual(
            GhostTargetPacingStrategy.even.elapsedFraction(at: 0.5),
            0.5, accuracy: 0.00001
        )
        XCTAssertGreaterThan(
            GhostTargetPacingStrategy.negativeSplit.elapsedFraction(at: 0.5),
            0.5
        )
        XCTAssertGreaterThan(
            GhostTargetPacingStrategy.progressive.elapsedFraction(at: 0.2),
            0.2
        )
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
