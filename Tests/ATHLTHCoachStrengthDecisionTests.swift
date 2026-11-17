import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCoachStrengthDecisionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_050_000_000)

    private func evidence(
        day: Int,
        load: Double = 60,
        met: Bool = true,
        count: Int = 3,
        workoutID: UUID = UUID()
    ) -> ATHLTHCoachStrengthDecision.Evidence {
        ATHLTHCoachStrengthDecision.Evidence(
            workoutID: workoutID,
            date: now.addingTimeInterval(-Double(day) * 86_400),
            workingSetIDs: (0..<count).map { _ in UUID() },
            minimumWorkingWeightKg: load,
            metTargets: met
        )
    }

    func testTwoCompleteSessionsOfferOnlyApprovedReview() {
        let first = evidence(day: 3)
        let second = evidence(day: 10)
        let result = ATHLTHCoachStrengthDecision.assess(
            evidence: [second, first],
            prescribedLoadKg: 60,
            incrementKg: 2.5
        )
        XCTAssertEqual(result.action, .reviewSmallIncrease)
        XCTAssertEqual(result.proposedWeightKg, 62.5)
        XCTAssertTrue(result.requiresUserApproval)
        XCTAssertEqual(result.sourceWorkoutIDs, [first.workoutID, second.workoutID])
        XCTAssertEqual(result.sourceSetIDs.count, 6)
    }

    func testOneGoodSessionIsNotEnoughAndNoIncrementIsInvented() {
        let one = evidence(day: 1)
        let result = ATHLTHCoachStrengthDecision.assess(
            evidence: [one], prescribedLoadKg: 60
        )
        XCTAssertEqual(result.action, .collectEvidence)
        XCTAssertNil(result.proposedWeightKg)

        let review = ATHLTHCoachStrengthDecision.assess(
            evidence: [one, evidence(day: 8)],
            prescribedLoadKg: 60
        )
        XCTAssertEqual(review.action, .reviewSmallIncrease)
        XCTAssertNil(review.proposedWeightKg)
    }

    func testMostRecentMissedTargetVetoesOlderSuccess() {
        let result = ATHLTHCoachStrengthDecision.assess(
            evidence: [
                evidence(day: 2, met: false),
                evidence(day: 9),
                evidence(day: 16)
            ],
            prescribedLoadKg: 60,
            incrementKg: 2.5
        )
        XCTAssertEqual(result.action, .hold)
        XCTAssertEqual(result.reason, .missedLatestTarget)
        XCTAssertNil(result.proposedWeightKg)
    }

    func testNewTargetWeightCannotUseEarlierLighterSets() {
        let result = ATHLTHCoachStrengthDecision.assess(
            evidence: [
                evidence(day: 2, load: 57.5),
                evidence(day: 9, load: 57.5)
            ],
            prescribedLoadKg: 60,
            incrementKg: 2.5
        )
        XCTAssertEqual(result.action, .hold)
    }

    func testInsufficientWorkingSetsAreNotTwoSuccessfulWorkouts() {
        let result = ATHLTHCoachStrengthDecision.assess(
            evidence: [
                evidence(day: 2, count: 1),
                evidence(day: 9)
            ],
            prescribedLoadKg: 60,
            incrementKg: 2.5
        )
        XCTAssertEqual(result.action, .hold)
        XCTAssertNil(result.proposedWeightKg)
    }

    func testRejectsUnrealisticAndNonFiniteIncrements() {
        for increment in [50.0, 3.0, .infinity, .nan, -1.0] {
            let result = ATHLTHCoachStrengthDecision.assess(
                evidence: [evidence(day: 1, load: 10), evidence(day: 7, load: 10)],
                prescribedLoadKg: 10,
                incrementKg: increment
            )
            XCTAssertEqual(result.action, .hold)
            XCTAssertNil(result.proposedWeightKg)
        }
    }

    func testInvalidPrescriptionDoesNotProduceNumericalSuggestion() {
        for weight in [0.0, -10.0, .nan, .infinity] {
            let result = ATHLTHCoachStrengthDecision.assess(
                evidence: [evidence(day: 1), evidence(day: 8)],
                prescribedLoadKg: weight, incrementKg: 2.5
            )
            XCTAssertEqual(result.action, .collectEvidence)
            XCTAssertNil(result.proposedWeightKg)
        }
    }

    func testSameWorkoutCannotCountTwiceAsTwoSessions() {
        let id = UUID()
        let result = ATHLTHCoachStrengthDecision.assess(
            evidence: [
                evidence(day: 2, workoutID: id),
                evidence(day: 9, workoutID: id)
            ],
            prescribedLoadKg: 60,
            incrementKg: 2.5
        )
        XCTAssertEqual(result.action, .collectEvidence)
    }
}
