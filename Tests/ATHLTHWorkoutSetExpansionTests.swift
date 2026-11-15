import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutSetExpansionTests: XCTestCase {
    func testIndividualSetsKeepLoadsRepsAndPauses() {
        var original = WorkoutTemplateBlock(
            sequence: 3, kind: .exercise,
            title: "Knebøy", exerciseSlug: "squat",
            distanceMeters: nil, repetitions: 8,
            durationSeconds: nil, targetWeightKilograms: 55,
            loadNote: nil, notes: "Hold kontrollen",
            phase: .main
        )
        original.setCount = 3
        original.restBetweenSetsSeconds = 90

        var separated = ATHLTHWorkoutSetExpansion.separateSets(in: original)
        XCTAssertEqual(separated.map(\.kind),
                       [.exercise, .rest, .exercise, .rest, .exercise])
        XCTAssertEqual(separated.filter { $0.kind == .rest }
                       .compactMap(\.durationSeconds), [90, 90])
        XCTAssertEqual(separated.filter { $0.kind == .exercise }
                       .compactMap(\.repetitions), [8, 8, 8])
        XCTAssertTrue(separated.filter { $0.kind == .exercise }
            .allSatisfy { $0.exerciseSlug == "squat" })
        XCTAssertTrue(separated.filter { $0.kind == .exercise }
            .allSatisfy { $0.setCount == nil })

        separated[2].targetWeightKilograms = 60
        separated[4].repetitions = 6
        XCTAssertEqual(separated[0].targetWeightKilograms, 55)
        XCTAssertEqual(separated[2].targetWeightKilograms, 60)
        XCTAssertEqual(separated[4].repetitions, 6)
        XCTAssertEqual(
            ATHLTHWorkoutDurationEstimator.minutes(for: separated),
            ATHLTHWorkoutDurationEstimator.minutes(for: [original])
        )
    }

    func testSingleSetIsNotExpanded() {
        let original = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise,
            title: "Armheving", exerciseSlug: nil,
            distanceMeters: nil, repetitions: 10,
            durationSeconds: nil, targetWeightKilograms: nil,
            loadNote: nil, notes: nil
        )
        XCTAssertEqual(ATHLTHWorkoutSetExpansion.separateSets(in: original),
                       [original])
    }
    func testFreeStrengthIsOneTimedWorkoutWithoutRepetitions() {
        let block = ATHLTHFreeStrengthRecipePolicy.make()
        XCTAssertTrue(ATHLTHFreeStrengthRecipePolicy.isFreeStrength(block))
        XCTAssertEqual(block.setCount, 1)
        XCTAssertNil(block.repetitions)
        XCTAssertNil(block.restBetweenSetsSeconds)
        XCTAssertNil(block.individualSetTargets)
        XCTAssertEqual(block.durationSeconds, 45 * 60)
        XCTAssertEqual(block.resolvedPhase, .main)
        XCTAssertEqual(ATHLTHWorkoutSetExpansion.separateSets(in: block).count, 1)
    }

    func testLegacyFreeStrengthThreeSetsIsNormalizedNotDuplicated() {
        var legacy = ATHLTHFreeStrengthRecipePolicy.make(phase: .warmup)
        legacy.title = "Free Strength Training"
        legacy.durationSeconds = nil
        legacy.setCount = 3
        legacy.repetitions = 10
        legacy.restBetweenSetsSeconds = 90
        let normalized = ATHLTHFreeStrengthRecipePolicy.normalized(legacy)
        XCTAssertEqual(normalized.setCount, 1)
        XCTAssertNil(normalized.repetitions)
        XCTAssertEqual(normalized.durationSeconds, 2_700)
        XCTAssertNil(normalized.restBetweenSetsSeconds)
        XCTAssertEqual(normalized.resolvedPhase, .warmup)
        XCTAssertEqual(normalized.editorDragID, legacy.editorDragID)
        XCTAssertEqual(
            ATHLTHWorkoutNameSuggestion.displayStepTitle(normalized),
            ATHLTHLocalization.choose(
                english: "Free strength training", norwegian: "Fri styrketrening"
            )
        )
    }

    func testRegularStrengthKeepsSetsAndRest() {
        var squat = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Squat", exerciseSlug: "squat",
            distanceMeters: nil, repetitions: 10, durationSeconds: nil,
            targetWeightKilograms: 60, loadNote: nil, notes: nil, phase: .main
        )
        squat.setCount = 3
        squat.restBetweenSetsSeconds = 90
        XCTAssertEqual(ATHLTHFreeStrengthRecipePolicy.normalized(squat), squat)
    }

}
