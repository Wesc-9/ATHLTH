import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCoachStrengthRepetitionVolumeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_050_000_000)

    private func sample(
        daysAgo: Int,
        reps: Int = 8,
        load: Double = 50,
        met: Bool = true,
        reserve: Bool = true,
        workoutID: UUID = UUID()
    ) -> ATHLTHCoachStrengthRepetitionVolume.Session {
        ATHLTHCoachStrengthRepetitionVolume.Session(
            workoutID: workoutID,
            date: now.addingTimeInterval(-Double(daysAgo) * 86_400),
            workingSetIDs: [UUID(), UUID(), UUID()],
            minimumReps: reps,
            minimumWeightKg: load,
            allTargetsMet: met,
            effortSupportsMore: reserve
        )
    }

    private var range: ATHLTHCoachStrengthRepetitionVolume.RepRange {
        ATHLTHCoachStrengthRepetitionVolume.RepRange(lower: 6, upper: 12)!
    }

    func testValidRangeMustBeExplicitAndBounded() {
        XCTAssertNil(ATHLTHCoachStrengthRepetitionVolume.RepRange(
            lower: 8, upper: 8
        ))
        XCTAssertNil(ATHLTHCoachStrengthRepetitionVolume.RepRange(
            lower: 0, upper: 50
        ))
        XCTAssertNotNil(range)
    }

    func testTwoRecordedSessionsWithVerifiedReservePermitOneRepOnly() {
        let result = ATHLTHCoachStrengthRepetitionVolume.assess(
            sessions: [sample(daysAgo: 3), sample(daysAgo: 10)],
            goal: .buildMuscle,
            range: range,
            prescribedReps: 8,
            prescribedLoadKg: 50
        )
        XCTAssertEqual(result.action, .reviewOneMoreRep)
        XCTAssertEqual(result.proposedReps, 9)
        XCTAssertNil(result.proposedAdditionalSets)
        XCTAssertTrue(result.requiresUserApproval)
        XCTAssertEqual(result.sourceWorkoutIDs.count, 2)
        XCTAssertEqual(result.sourceSetIDs.count, 6)
    }

    func testNoGoalOrNoRangeMeansNoUnsolicitedProgression() {
        let ineligibleGoals: [TrainingPlanGoalType?] = [nil, .improveFitness, .maintain]
        for goal in ineligibleGoals {
            let result = ATHLTHCoachStrengthRepetitionVolume.assess(
                sessions: [sample(daysAgo: 3), sample(daysAgo: 10)],
                goal: goal,
                range: range,
                prescribedReps: 8,
                prescribedLoadKg: 50
            )
            XCTAssertEqual(result.action, .collectEvidence)
            XCTAssertNil(result.proposedReps)
        }
        let result = ATHLTHCoachStrengthRepetitionVolume.assess(
            sessions: [sample(daysAgo: 3), sample(daysAgo: 10)],
            goal: .buildMuscle,
            range: nil,
            prescribedReps: 8,
            prescribedLoadKg: 50
        )
        XCTAssertEqual(result.reason, .goalOrRangeMissing)
    }

    func testOneSessionCannotCountAsTwoEvenWhenRepeated() {
        let id = UUID()
        let result = ATHLTHCoachStrengthRepetitionVolume.assess(
            sessions: [
                sample(daysAgo: 2, workoutID: id),
                sample(daysAgo: 9, workoutID: id)
            ],
            goal: .buildMuscle, range: range,
            prescribedReps: 8, prescribedLoadKg: 50
        )
        XCTAssertEqual(result.action, .collectEvidence)
    }

    func testNewestHardOrMissedSessionVetoesIncrease() {
        let baseline = sample(daysAgo: 10)
        for newest in [
            sample(daysAgo: 2, met: false),
            sample(daysAgo: 2, reserve: false),
            sample(daysAgo: 2, load: 45)
        ] {
            let result = ATHLTHCoachStrengthRepetitionVolume.assess(
                sessions: [newest, baseline],
                goal: .getStronger, range: range,
                prescribedReps: 8, prescribedLoadKg: 50
            )
            XCTAssertNotEqual(result.action, .reviewOneMoreRep)
            XCTAssertNil(result.proposedReps)
        }
    }

    func testUpperLimitNeverIncreasesRepetitions() {
        let result = ATHLTHCoachStrengthRepetitionVolume.assess(
            sessions: [sample(daysAgo: 2, reps: 12), sample(daysAgo: 9, reps: 12)],
            goal: .buildMuscle, range: range,
            prescribedReps: 12, prescribedLoadKg: 50
        )
        XCTAssertEqual(result.action, .hold)
        XCTAssertNil(result.proposedReps)
    }

    func testPotentialVolumeReviewHasNoAutomaticSetCount() {
        let result = ATHLTHCoachStrengthRepetitionVolume.assess(
            sessions: [
                sample(daysAgo: 1, reps: 12),
                sample(daysAgo: 9, reps: 12),
                sample(daysAgo: 18, reps: 12)
            ],
            goal: .buildMuscle, range: range,
            prescribedReps: 12, prescribedLoadKg: 50
        )
        XCTAssertEqual(result.action, .reviewTrainingVolume)
        XCTAssertNil(result.proposedAdditionalSets)
        XCTAssertNil(result.proposedReps)
        XCTAssertTrue(result.requiresUserApproval)
    }

    func testNoVolumeReviewForStrengthGoal() {
        let result = ATHLTHCoachStrengthRepetitionVolume.assess(
            sessions: [
                sample(daysAgo: 1, reps: 12),
                sample(daysAgo: 9, reps: 12),
                sample(daysAgo: 18, reps: 12)
            ],
            goal: .getStronger, range: range,
            prescribedReps: 12, prescribedLoadKg: 50
        )
        XCTAssertEqual(result.action, .hold)
    }

    func testInvalidRepetitionOrWeightPrescriptionHasNoProposal() {
        for reps in [0, 5, 13] {
            let result = ATHLTHCoachStrengthRepetitionVolume.assess(
                sessions: [sample(daysAgo: 2), sample(daysAgo: 9)],
                goal: .buildMuscle, range: range,
                prescribedReps: reps, prescribedLoadKg: 50
            )
            XCTAssertEqual(result.action, .collectEvidence)
            XCTAssertNil(result.proposedReps)
        }
    }
}
