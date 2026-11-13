import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutPacePlanTests: XCTestCase {
    private func run(
        _ sequence: Int, phase: WorkoutPhaseKind,
        zoneLabel: String? = nil
    ) -> WorkoutTemplateBlock {
        var step = WorkoutTemplateBlock(
            sequence: sequence, kind: .run, title: "Run \(sequence)",
            exerciseSlug: nil, distanceMeters: 2_000,
            repetitions: nil, durationSeconds: nil,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: phase
        )
        step.sourceIntensityZoneLabel = zoneLabel
        if zoneLabel != nil {
            step.targetHeartRatePercentMin = 80
            step.targetHeartRatePercentMax = 90
        }
        return step
    }

    func testSharedTargetChangesOnlyWorkNotWarmupOrRecovery() {
        let original = [
            run(1, phase: .warmup),
            run(2, phase: .main, zoneLabel: "Z4"),
            run(3, phase: .recovery),
            run(4, phase: .main, zoneLabel: "Z4")
        ]
        let selected = ATHLTHWorkoutPacePlan(
            scope: .allWork, sharedPaceSecondsPerKilometer: 305
        )
        let updated = ATHLTHWorkoutQuickGoalApplier.apply(.pacePlan(selected), to: original)
        XCTAssertNil(updated[0].targetPaceSecondsPerKilometer)
        XCTAssertEqual(updated[1].targetPaceSecondsPerKilometer, 305)
        XCTAssertNil(updated[2].targetPaceSecondsPerKilometer)
        XCTAssertEqual(updated[3].targetPaceSecondsPerKilometer, 305)
        XCTAssertEqual(updated[1].sourceIntensityZoneLabel, "Z4")
        XCTAssertEqual(updated[1].targetHeartRatePercentMin, 80)
        XCTAssertEqual(updated[1].targetHeartRatePercentMax, 90)
        XCTAssertNil(original[1].targetPaceSecondsPerKilometer)
    }

    func testCheckedTargetsCanIncludeWarmupAndRecoveryWithoutTouchingRest() {
        let original = [
            run(1, phase: .warmup),
            run(2, phase: .main),
            run(3, phase: .recovery),
            WorkoutTemplateBlock(
                sequence: 4, kind: .rest, title: "Passive pause",
                exerciseSlug: nil, distanceMeters: nil,
                repetitions: nil, durationSeconds: 90,
                targetWeightKilograms: nil, loadNote: nil,
                notes: nil, phase: .recovery
            )
        ]
        let selection = ATHLTHWorkoutPacePlan(
            scope: .selectedSteps, sharedPaceSecondsPerKilometer: 370,
            selectedIndices: [0, 2, 3]
        )
        let updated = ATHLTHWorkoutQuickGoalApplier.apply(.pacePlan(selection), to: original)
        XCTAssertEqual(updated[0].targetPaceSecondsPerKilometer, 370)
        XCTAssertNil(updated[1].targetPaceSecondsPerKilometer)
        XCTAssertEqual(updated[2].targetPaceSecondsPerKilometer, 370)
        XCTAssertNil(updated[3].targetPaceSecondsPerKilometer)
        XCTAssertEqual(updated[3].durationSeconds, 90)
    }

    func testIndividualTargetsFollowOriginalStepOrder() {
        let original = [run(1, phase: .warmup), run(2, phase: .main), run(3, phase: .main)]
        let plan = ATHLTHWorkoutPacePlan(
            scope: .individual, sharedPaceSecondsPerKilometer: 330,
            selectedIndices: [1, 2],
            individualPaces: [1: 300, 2: 315]
        )
        let updated = ATHLTHWorkoutQuickGoalApplier.apply(.pacePlan(plan), to: original)
        XCTAssertNil(updated[0].targetPaceSecondsPerKilometer)
        XCTAssertEqual(updated[1].targetPaceSecondsPerKilometer, 300)
        XCTAssertEqual(updated[2].targetPaceSecondsPerKilometer, 315)
        XCTAssertEqual(updated.map(\.sequence), original.map(\.sequence))
        XCTAssertEqual(updated.map(\.distanceMeters), original.map(\.distanceMeters))
    }
}
