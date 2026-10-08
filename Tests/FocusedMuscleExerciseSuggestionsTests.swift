import XCTest
@testable import ATHLTH

final class FocusedMuscleExerciseSuggestionsTests: XCTestCase {
    func testBicepsPriorityProducesEditableExercisesWithoutInventingWeights() {
        let exercises = FocusedMuscleExerciseSuggestions.makeExercises(
            for: "biceps",
            sessionIndex: 0
        )

        XCTAssertEqual(exercises.count, 2)
        XCTAssertTrue(exercises.allSatisfy { $0.embeddedExercise.primaryMuscles.contains("biceps") })
        XCTAssertTrue(exercises.allSatisfy { $0.targetWeightKilograms == nil })
        XCTAssertTrue(exercises.allSatisfy { $0.exerciseID == nil })
        XCTAssertTrue(exercises.allSatisfy { $0.sets == 3 })
        XCTAssertEqual(Set(exercises.map(\.id)).count, exercises.count)
    }

    func testBicepsSuggestionsAlternateAcrossStrengthDays() {
        let first = FocusedMuscleExerciseSuggestions.makeExercises(
            for: "biceps",
            sessionIndex: 0
        )
        let second = FocusedMuscleExerciseSuggestions.makeExercises(
            for: "biceps",
            sessionIndex: 1
        )

        XCTAssertFalse(first.isEmpty)
        XCTAssertFalse(second.isEmpty)
        XCTAssertNotEqual(
            first.map { $0.embeddedExercise.name },
            second.map { $0.embeddedExercise.name }
        )
    }

    func testUnrecognisedMuscleDoesNotGenerateUnreliableExercises() {
        XCTAssertTrue(
            FocusedMuscleExerciseSuggestions.makeExercises(
                for: "not-a-muscle",
                sessionIndex: 0
            ).isEmpty
        )
    }
}
