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
}
