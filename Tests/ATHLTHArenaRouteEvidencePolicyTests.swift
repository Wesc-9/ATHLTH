import Foundation
import XCTest
@testable import ATHLTH

/// Route/GPS evidence is a device-reported suggestion, never automatic points.
final class ATHLTHArenaRouteEvidencePolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let target = 5_000.0

    private func workout(
        distance: Double = 5_000,
        duration: Double = 1_500,
        walking: Bool = false
    ) -> SocialPublishableWorkout {
        let recorded = PhoneWorkout(
            walking: walking,
            start: start,
            end: start.addingTimeInterval(duration),
            accumulatedSeconds: duration,
            lastCheckpoint: start.addingTimeInterval(duration),
            distanceMeters: distance
        )
        return SocialPublishableWorkout(phoneWorkout: recorded)
    }

    private func eligible(
        _ workout: SocialPublishableWorkout,
        startsAt: Date? = nil,
        endsAt: Date? = nil
    ) -> Bool {
        ATHLTHArenaRouteEvidencePolicy.eligibleWorkout(
            workout,
            plannedDistanceMeters: target,
            startsAt: startsAt ?? start.addingTimeInterval(-60),
            endsAt: endsAt ?? start.addingTimeInterval(86_400),
            now: start.addingTimeInterval(87_000)
        )
    }

    func testQualifiedOutdoorRunInsideCompetitionWindow() {
        XCTAssertTrue(eligible(workout()))
    }

    func testRouteRunOutsideCompetitionWindowIsRejected() {
        XCTAssertFalse(eligible(
            workout(),
            startsAt: start.addingTimeInterval(5)
        ))
        XCTAssertFalse(eligible(
            workout(),
            endsAt: start.addingTimeInterval(1_000)
        ))
    }

    func testDistanceToleranceAndImpossibleSpeed() {
        XCTAssertTrue(eligible(workout(distance: 5_200)))
        XCTAssertFalse(eligible(workout(distance: 5_300)))
        XCTAssertFalse(eligible(workout(distance: 5_000, duration: 100)))
    }

    func testWalkingDoesNotQualifyForRunningRoute() {
        XCTAssertFalse(eligible(workout(walking: true)))
    }

    func testStrongGPSProofQualifiesLocallyOnly() {
        XCTAssertTrue(ATHLTHArenaRouteEvidencePolicy.eligibleProof(
            matchPercent: 95,
            startGapMeters: 15,
            endGapMeters: 30,
            measuredDistanceMeters: 5_050,
            plannedDistanceMeters: target,
            elapsedSeconds: 1_500
        ))
    }

    func testGPSProofRejectsPoorCoverageAndStartFinishGaps() {
        XCTAssertFalse(proof(match: 89, startGap: 0, endGap: 0))
        XCTAssertFalse(proof(match: 96, startGap: 121, endGap: 0))
        XCTAssertFalse(proof(match: 96, startGap: 0, endGap: 121))
    }

    func testGPSProofRejectsInvalidPercentAndDistance() {
        XCTAssertFalse(proof(match: .infinity, startGap: 0, endGap: 0))
        XCTAssertFalse(proof(match: 101, startGap: 0, endGap: 0))
        XCTAssertFalse(ATHLTHArenaRouteEvidencePolicy.eligibleProof(
            matchPercent: 99,
            startGapMeters: 0,
            endGapMeters: 0,
            measuredDistanceMeters: 5_500,
            plannedDistanceMeters: target,
            elapsedSeconds: 1_500
        ))
    }

    func testGPSProofRejectsImpossibleTime() {
        XCTAssertFalse(ATHLTHArenaRouteEvidencePolicy.eligibleProof(
            matchPercent: 99,
            startGapMeters: 0,
            endGapMeters: 0,
            measuredDistanceMeters: target,
            plannedDistanceMeters: target,
            elapsedSeconds: 50
        ))
    }

    private func proof(
        match: Double, startGap: Double, endGap: Double
    ) -> Bool {
        ATHLTHArenaRouteEvidencePolicy.eligibleProof(
            matchPercent: match,
            startGapMeters: startGap,
            endGapMeters: endGap,
            measuredDistanceMeters: target,
            plannedDistanceMeters: target,
            elapsedSeconds: 1_500
        )
    }
}
