import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHArenaSuggestedRankingTests: XCTestCase {
    private let roundID = UUID()
    private let initialDate = Date(timeIntervalSince1970: 1_790_000_000)

    private func workout(
        slot: UUID,
        value: Double,
        metric: String,
        round: UUID? = nil,
        user: UUID? = nil,
        routeMatchPercent: Double? = nil
    ) -> ATHLTHArenaWorkoutEvidence {
        ATHLTHArenaWorkoutEvidence(
            id: UUID(),
            seriesID: UUID(),
            roundID: round ?? roundID,
            slotID: slot,
            userID: user ?? UUID(),
            sourceWorkoutID: UUID(),
            source: "iphone",
            activityType: "running",
            startedAt: initialDate,
            endedAt: initialDate.addingTimeInterval(1_500),
            metricType: metric,
            metricValue: value,
            reportedDistanceMeters: 5_000,
            reportedRouteMatchPercent: routeMatchPercent,
            verificationLevel: "participant_reported"
        )
    }

    func testFastestRunUsesBestTimeAndNeverLongestTime() {
        let a = UUID()
        let b = UUID()
        let standings = ATHLTHArenaSuggestedRanking.standings(
            template: .fastest5K,
            roundID: roundID,
            evidence: [
                workout(slot: a, value: 1_400, metric: "elapsed_seconds"),
                workout(slot: a, value: 1_200, metric: "elapsed_seconds"),
                workout(slot: b, value: 1_250, metric: "elapsed_seconds")
            ]
        )
        XCTAssertEqual(standings.map(\.slotID), [a, b])
        XCTAssertEqual(standings.first?.result, 1_200)
    }

    func testDistanceSumsAndExcludesUnrelatedMetric() {
        let a = UUID()
        let b = UUID()
        let standings = ATHLTHArenaSuggestedRanking.standings(
            template: .mostDistance,
            roundID: roundID,
            evidence: [
                workout(slot: a, value: 2_000, metric: "distance_meters"),
                workout(slot: a, value: 4_000, metric: "distance_meters"),
                workout(slot: b, value: 4_500, metric: "distance_meters"),
                workout(slot: b, value: 1_400, metric: "elapsed_seconds")
            ]
        )
        XCTAssertEqual(standings.map(\.slotID), [a, b])
        XCTAssertEqual(standings.first?.result, 6_000)
    }

    func testCountUsesNumberOfSharedWorkouts() {
        let a = UUID()
        let b = UUID()
        let standings = ATHLTHArenaSuggestedRanking.standings(
            template: .mostWorkouts,
            roundID: roundID,
            evidence: [
                workout(slot: a, value: 1, metric: "completed_workout"),
                workout(slot: a, value: 1, metric: "completed_workout"),
                workout(slot: b, value: 1, metric: "completed_workout")
            ]
        )
        XCTAssertEqual(standings.first?.result, 2)
    }

    func testEqualTimesRequireExplicitGroupResolution() {
        let standings = ATHLTHArenaSuggestedRanking.standings(
            template: .fastest1K,
            roundID: roundID,
            evidence: [
                workout(slot: UUID(), value: 280, metric: "elapsed_seconds"),
                workout(slot: UUID(), value: 280, metric: "elapsed_seconds")
            ]
        )
        XCTAssertTrue(ATHLTHArenaSuggestedRanking.hasTieAtTop(standings))
    }

    func testSuggestedWinnerNeedsEvidenceFromEveryAthlete() {
        let a = UUID()
        let b = UUID()
        let suggestion = ATHLTHArenaSuggestedRanking.eligibleSuggestion(
            template: .fastest5K,
            scoring: .winner,
            roundID: roundID,
            requiredSlots: [a, b],
            evidence: [workout(slot: a, value: 1_300, metric: "elapsed_seconds")]
        )
        XCTAssertNil(suggestion)
    }

    func testCompleteUnequalResultsProduceWinnerSuggestion() {
        let a = UUID()
        let b = UUID()
        let suggestion = ATHLTHArenaSuggestedRanking.eligibleSuggestion(
            template: .fastest5K,
            scoring: .winner,
            roundID: roundID,
            requiredSlots: [a, b],
            evidence: [
                workout(slot: a, value: 1_300, metric: "elapsed_seconds"),
                workout(slot: b, value: 1_250, metric: "elapsed_seconds")
            ]
        )
        XCTAssertEqual(suggestion, [b])
    }

    func testEqualTimesNeverProduceAutomaticSuggestion() {
        let a = UUID()
        let b = UUID()
        let suggestion = ATHLTHArenaSuggestedRanking.eligibleSuggestion(
            template: .fastest1K,
            scoring: .winner,
            roundID: roundID,
            requiredSlots: [a, b],
            evidence: [
                workout(slot: a, value: 250, metric: "elapsed_seconds"),
                workout(slot: b, value: 250, metric: "elapsed_seconds")
            ]
        )
        XCTAssertNil(suggestion)
    }

    func testPodiumTieAtThirdPlaceRequiresManualReview() {
        let slots = (0..<4).map { _ in UUID() }
        let evidence = zip(slots, [10_000.0, 9_000, 8_000, 8_000])
            .map { slot, distance in
                workout(slot: slot, value: distance, metric: "distance_meters")
            }
        let suggestion = ATHLTHArenaSuggestedRanking.eligibleSuggestion(
            template: .mostDistance,
            scoring: .podium,
            roundID: roundID,
            requiredSlots: slots,
            evidence: evidence
        )
        XCTAssertNil(suggestion)
    }

    func testRivalTargetUsesOnlyOtherParticipantsValidRouteReports() {
        let me = UUID()
        let other = UUID()
        let anotherRound = UUID()
        let report: [ATHLTHArenaWorkoutEvidence] = [
            workout(slot: UUID(), value: 500, metric: "elapsed_seconds",
                    user: me, routeMatchPercent: 98),
            workout(slot: UUID(), value: 900, metric: "elapsed_seconds",
                    user: other, routeMatchPercent: 92),
            workout(slot: UUID(), value: 400, metric: "elapsed_seconds",
                    round: anotherRound, user: other, routeMatchPercent: 99),
            workout(slot: UUID(), value: 200, metric: "elapsed_seconds",
                    user: other),
            workout(slot: UUID(), value: 600, metric: "elapsed_seconds",
                    user: other, routeMatchPercent: 75),
            workout(slot: UUID(), value: 1, metric: "completed_workout",
                    user: other, routeMatchPercent: 95)
        ]
        XCTAssertEqual(
            ATHLTHArenaSuggestedRanking.fastestSharedRivalTime(
                roundID: roundID,
                currentUserID: me,
                evidence: report
            ),
            900
        )
    }

    func testRivalTargetMissingEvidenceDoesNotInventGhostTime() {
        XCTAssertNil(
            ATHLTHArenaSuggestedRanking.fastestSharedRivalTime(
                roundID: roundID,
                currentUserID: UUID(),
                evidence: []
            )
        )
    }

    func testFinishedLiveDuelResultMatchesReportedWinner() {
        let sender = UUID()
        let recipient = UUID()
        let candidate = ATHLTHArenaLiveDuelReview.candidate(
            senderID: sender,
            recipientID: recipient,
            senderSeconds: 1_500,
            recipientSeconds: 1_450,
            reportedWinnerID: recipient,
            isFinished: true
        )
        XCTAssertEqual(candidate?.winnerID, recipient)
        XCTAssertEqual(candidate?.marginSeconds, 50)
    }

    func testLiveDuelRequiresBothTimesAndCompletedRace() {
        let a = UUID(), b = UUID()
        XCTAssertNil(ATHLTHArenaLiveDuelReview.candidate(
            senderID: a, recipientID: b, senderSeconds: nil,
            recipientSeconds: 1_500, reportedWinnerID: b, isFinished: true
        ))
        XCTAssertNil(ATHLTHArenaLiveDuelReview.candidate(
            senderID: a, recipientID: b, senderSeconds: 1_400,
            recipientSeconds: 1_500, reportedWinnerID: a, isFinished: false
        ))
        XCTAssertNil(ATHLTHArenaLiveDuelReview.candidate(
            senderID: a, recipientID: b, senderSeconds: .infinity,
            recipientSeconds: 1_500, reportedWinnerID: b, isFinished: true
        ))
    }

    func testLiveDuelDisagreementNeverSuggestsWinner() {
        let a = UUID(), b = UUID()
        XCTAssertNil(ATHLTHArenaLiveDuelReview.candidate(
            senderID: a, recipientID: b, senderSeconds: 1_400,
            recipientSeconds: 1_500, reportedWinnerID: b, isFinished: true
        ))
    }

    func testTiedLiveDuelHasNoAutomaticWinner() {
        let a = UUID(), b = UUID()
        let candidate = ATHLTHArenaLiveDuelReview.candidate(
            senderID: a, recipientID: b, senderSeconds: 1_500.0,
            recipientSeconds: 1_500.3, reportedWinnerID: nil, isFinished: true
        )
        XCTAssertNotNil(candidate)
        XCTAssertNil(candidate?.winnerID)
        XCTAssertNil(ATHLTHArenaLiveDuelReview.candidate(
            senderID: a, recipientID: b, senderSeconds: 1_500.0,
            recipientSeconds: 1_500.3, reportedWinnerID: a, isFinished: true
        ))
    }

    func testCustomRoundsDoNotInferUnsupportedResults() {
        let standings = ATHLTHArenaSuggestedRanking.standings(
            template: .custom,
            roundID: roundID,
            evidence: [workout(slot: UUID(), value: 3_000, metric: "distance_meters")]
        )
        XCTAssertTrue(standings.isEmpty)
    }
}
