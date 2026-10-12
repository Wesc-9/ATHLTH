import Foundation
import XCTest
@testable import ATHLTH

/// Synchronized duel telemetry is advisory, never authoritative scoring.
final class ATHLTHLiveGhostRacingTelemetryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func eligible(
        age: TimeInterval,
        distance: Double = 2_000,
        elapsed: Double = 700,
        expiresIn: TimeInterval = 90
    ) -> Bool {
        ATHLTHLiveGhostRacingTelemetry.canCompare(
            updatedAt: now.addingTimeInterval(-age),
            expiresAt: now.addingTimeInterval(expiresIn),
            distanceMeters: distance,
            elapsedSeconds: elapsed,
            now: now
        )
    }

    func testBothAthletesResolveDifferentCorrectOpponents() {
        let host = UUID(), guest = UUID()
        XCTAssertEqual(ATHLTHLiveGhostRacingTelemetry.opponentID(
            ownerID: host, otherID: guest, viewerID: host
        ), guest)
        XCTAssertEqual(ATHLTHLiveGhostRacingTelemetry.opponentID(
            ownerID: host, otherID: guest, viewerID: guest
        ), host)
    }

    func testUnrelatedUserCannotUsePrivateDuelAsWorkoutComparison() {
        XCTAssertNil(ATHLTHLiveGhostRacingTelemetry.opponentID(
            ownerID: UUID(), otherID: UUID(), viewerID: UUID()
        ))
    }

    func testHostWithoutOpponentCannotInventRunner() {
        let host = UUID()
        XCTAssertNil(ATHLTHLiveGhostRacingTelemetry.opponentID(
            ownerID: host, otherID: nil, viewerID: host
        ))
    }

    func testFreshOpponentPositionPermitsGapComparison() {
        XCTAssertTrue(eligible(age: 2))
        XCTAssertTrue(eligible(age: 18))
    }

    func testDelayedOrExpiredOpponentsNeverProducePassing() {
        XCTAssertFalse(eligible(age: 18.1))
        XCTAssertFalse(eligible(age: 120))
        XCTAssertFalse(eligible(age: 1, expiresIn: -1))
    }

    func testFutureOrCorruptedGPSNeverProducesPassing() {
        XCTAssertFalse(eligible(age: -6))
        XCTAssertFalse(eligible(age: .infinity))
        XCTAssertFalse(eligible(age: 2, distance: .nan))
        XCTAssertFalse(eligible(age: 2, distance: -5))
    }

    func testImpossibleDistanceAndWorkoutTimeCannotProducePassing() {
        XCTAssertFalse(eligible(age: 2, distance: 5_000, elapsed: 10))
        XCTAssertFalse(eligible(age: 2, distance: 50, elapsed: -1))
        XCTAssertFalse(eligible(age: 2, distance: 50, elapsed: .infinity))
        XCTAssertFalse(eligible(age: 2, distance: 50, elapsed: 90_000))
    }

    func testSynchronizedRaceMustMatchItsExactChallenge() {
        let duel = UUID()
        XCTAssertTrue(ATHLTHLiveGhostRacingTelemetry.matchesWorkout(
            challengeID: duel,
            selectedRouteKey: duel,
            localComparisonRouteID: duel
        ))
        XCTAssertTrue(ATHLTHLiveGhostRacingTelemetry.matchesWorkout(
            challengeID: duel,
            selectedRouteKey: nil,
            localComparisonRouteID: duel
        ))
    }

    func testSynchronizedRaceNeverComparesUnknownOrOtherWorkout() {
        let duel = UUID()
        XCTAssertFalse(ATHLTHLiveGhostRacingTelemetry.matchesWorkout(
            challengeID: duel,
            selectedRouteKey: duel,
            localComparisonRouteID: nil
        ))
        XCTAssertFalse(ATHLTHLiveGhostRacingTelemetry.matchesWorkout(
            challengeID: duel,
            selectedRouteKey: nil,
            localComparisonRouteID: UUID()
        ))
        XCTAssertFalse(ATHLTHLiveGhostRacingTelemetry.matchesWorkout(
            challengeID: duel,
            selectedRouteKey: UUID(),
            localComparisonRouteID: duel
        ))
    }

    func testLegacyLiveFollowRetainsDistanceOnlyFallback() {
        XCTAssertTrue(ATHLTHLiveGhostRacingTelemetry.matchesWorkout(
            challengeID: nil,
            selectedRouteKey: nil,
            localComparisonRouteID: nil
        ))
        XCTAssertTrue(ATHLTHLiveGhostRacingTelemetry.matchesWorkout(
            challengeID: nil,
            selectedRouteKey: UUID(),
            localComparisonRouteID: nil
        ))
        let route = UUID()
        XCTAssertTrue(ATHLTHLiveGhostRacingTelemetry.matchesWorkout(
            challengeID: nil,
            selectedRouteKey: route,
            localComparisonRouteID: route
        ))
        XCTAssertFalse(ATHLTHLiveGhostRacingTelemetry.matchesWorkout(
            challengeID: nil,
            selectedRouteKey: route,
            localComparisonRouteID: UUID()
        ))
    }

    func testNoSignedInAthleteCannotResolveAnOpponent() {
        XCTAssertNil(ATHLTHLiveGhostRacingTelemetry.opponentID(
            ownerID: UUID(),
            otherID: UUID(),
            viewerID: nil
        ))
    }

    func testPhoneLocationMustBeFreshAtSourceBeforeSharing() {
        XCTAssertTrue(ATHLTHLiveGhostRacingTelemetry.freshLocalLocation(
            capturedAt: now.addingTimeInterval(-2), now: now
        ))
        XCTAssertTrue(ATHLTHLiveGhostRacingTelemetry.freshLocalLocation(
            capturedAt: now.addingTimeInterval(-25), now: now
        ))
        XCTAssertFalse(ATHLTHLiveGhostRacingTelemetry.freshLocalLocation(
            capturedAt: now.addingTimeInterval(-26), now: now
        ))
        XCTAssertFalse(ATHLTHLiveGhostRacingTelemetry.freshLocalLocation(
            capturedAt: now.addingTimeInterval(-300), now: now
        ))
    }

    func testFutureOrInvalidPhoneLocationDoesNotBecomeLiveAgain() {
        XCTAssertFalse(ATHLTHLiveGhostRacingTelemetry.freshLocalLocation(
            capturedAt: now.addingTimeInterval(6), now: now
        ))
        XCTAssertFalse(ATHLTHLiveGhostRacingTelemetry.freshLocalLocation(
            capturedAt: Date(timeIntervalSince1970: .infinity), now: now
        ))
    }

    func testRouteDeviationMustBePlausibleOrAbsent() {
        XCTAssertTrue(ATHLTHLiveGhostRacingTelemetry.acceptableDeviation(
            15, maximum: 120
        ))
        XCTAssertTrue(ATHLTHLiveGhostRacingTelemetry.acceptableDeviation(
            nil, maximum: 120
        ))
        XCTAssertFalse(ATHLTHLiveGhostRacingTelemetry.acceptableDeviation(
            121, maximum: 120
        ))
        XCTAssertFalse(ATHLTHLiveGhostRacingTelemetry.acceptableDeviation(
            -1, maximum: 120
        ))
        XCTAssertFalse(ATHLTHLiveGhostRacingTelemetry.acceptableDeviation(
            .nan, maximum: 120
        ))
    }
}
