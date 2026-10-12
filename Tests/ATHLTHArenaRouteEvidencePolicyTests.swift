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

    func testGPSAnalysisAndOriginalWorkoutMustBeConsistent() {
        XCTAssertTrue(ATHLTHArenaRouteEvidencePolicy.analysisMatchesWorkout(
            analyzedDistanceMeters: 4_980,
            analyzedDurationSeconds: 1_480,
            workoutDistanceMeters: 5_000,
            workoutDurationSeconds: 1_500
        ))
    }

    func testGPSAnalysisRejectsUnrelatedPartialTrack() {
        XCTAssertFalse(ATHLTHArenaRouteEvidencePolicy.analysisMatchesWorkout(
            analyzedDistanceMeters: 2_000,
            analyzedDurationSeconds: 700,
            workoutDistanceMeters: 5_000,
            workoutDurationSeconds: 1_500
        ))
    }

    func testGPSAnalysisRejectsInconsistentWorkoutTiming() {
        XCTAssertFalse(ATHLTHArenaRouteEvidencePolicy.analysisMatchesWorkout(
            analyzedDistanceMeters: 5_000,
            analyzedDurationSeconds: 1_000,
            workoutDistanceMeters: 5_000,
            workoutDurationSeconds: 1_600
        ))
    }

    func testGPSAnalysisAllowsReasonableRecordingPauseDifference() {
        XCTAssertTrue(ATHLTHArenaRouteEvidencePolicy.analysisMatchesWorkout(
            analyzedDistanceMeters: 4_900,
            analyzedDurationSeconds: 1_350,
            workoutDistanceMeters: 5_000,
            workoutDurationSeconds: 1_500
        ))
    }

    func testGPSAnalysisRejectsMissingAndInvalidMeasurements() {
        XCTAssertFalse(ATHLTHArenaRouteEvidencePolicy.analysisMatchesWorkout(
            analyzedDistanceMeters: 5_000,
            analyzedDurationSeconds: 1_500,
            workoutDistanceMeters: nil,
            workoutDurationSeconds: 1_500
        ))
        XCTAssertFalse(ATHLTHArenaRouteEvidencePolicy.analysisMatchesWorkout(
            analyzedDistanceMeters: .infinity,
            analyzedDurationSeconds: 1_500,
            workoutDistanceMeters: 5_000,
            workoutDurationSeconds: 1_500
        ))
    }

    func testRouteProofCannotBeReusedForAnotherRound() {
        let round = UUID()
        let proof = ATHLTHArenaRouteProof(
            roundID: round,
            matchPercent: 95,
            startGapMeters: 10,
            endGapMeters: 15,
            analyzedDistanceMeters: 4_950,
            analyzedDurationSeconds: 1_450
        )
        XCTAssertTrue(proof.belongs(to: round))
        XCTAssertFalse(proof.belongs(to: UUID()))
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
