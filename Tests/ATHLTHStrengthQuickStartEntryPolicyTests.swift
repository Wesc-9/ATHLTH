import XCTest
@testable import ATHLTH

final class ATHLTHStrengthQuickStartEntryPolicyTests: XCTestCase {
    func testExerciseEntryOpensExerciseSelectionEvenForAnEmptyQuickWorkout() {
        XCTAssertEqual(ATHLTHStrengthQuickStartEntryPolicy.initialType(
            requested: .exercises, hasStructuredBlocks: false,
            hasExercises: false
        ), .exercises)
    }

    func testFreeStrengthEntryNeverAccidentallyOpensExerciseSelection() {
        XCTAssertEqual(ATHLTHStrengthQuickStartEntryPolicy.initialType(
            requested: .free, hasStructuredBlocks: true,
            hasExercises: true
        ), .free)
    }

    func testSavedStructuredWorkoutKeepsItsPresetWhenNotOverridden() {
        XCTAssertEqual(ATHLTHStrengthQuickStartEntryPolicy.initialType(
            requested: nil, hasStructuredBlocks: true,
            hasExercises: false
        ), .workout)
        XCTAssertEqual(ATHLTHStrengthQuickStartEntryPolicy.initialType(
            requested: nil, hasStructuredBlocks: false,
            hasExercises: true
        ), .exercises)
    }
}
