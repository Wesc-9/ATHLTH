import XCTest
@testable import ATHLTH

final class ATHLTHUnifiedLibraryNavigationTests: XCTestCase {
    func testPlanAndWorkoutSourcesShareUnifiedPickerOptions() {
        XCTAssertEqual(ATHLTHUnifiedLibraryScope.allCases, [.athlth, .mine])
        XCTAssertNotEqual(
            ATHLTHUnifiedLibraryScope.athlth.title,
            ATHLTHUnifiedLibraryScope.mine.title
        )
    }

    func testNorwegianMuscleFiltersAreAlphabeticalWithoutChangingRawKeys() {
        let source = ["Shoulders", "Back", "Core", "Chest", "Biceps"]
        let localized = [
            "Shoulders": "Skuldre",
            "Back": "Rygg",
            "Core": "Mage",
            "Chest": "Bryst",
            "Biceps": "Biceps"
        ]
        let sorted = ATHLTHExerciseMuscleFilterPresentation.sorted(source) {
            localized[$0] ?? $0
        }
        XCTAssertEqual(sorted, ["Biceps", "Chest", "Core", "Back", "Shoulders"])
        XCTAssertEqual(source.first, "Shoulders") // no mutation of catalog order
    }

    func testBackMusclesUseTheBackAnatomyFigure() {
        for group in ["Back", "Triceps", "Glutes", "Hamstrings", "Calves"] {
            XCTAssertTrue(ATHLTHExerciseMuscleFilterPresentation.isBackMuscle(group))
        }
        for group in ["Chest", "Shoulders", "Core", "Biceps"] {
            XCTAssertFalse(ATHLTHExerciseMuscleFilterPresentation.isBackMuscle(group))
        }
    }
}
