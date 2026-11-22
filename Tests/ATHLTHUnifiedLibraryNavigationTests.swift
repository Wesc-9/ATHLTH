import XCTest
@testable import ATHLTH

final class ATHLTHUnifiedLibraryNavigationTests: XCTestCase {
    func testPlanAndWorkoutSourcesShareUnifiedPickerOptions() {
        // All shared library pickers expose Favorites alongside ATHLTH and Mine.
        XCTAssertEqual(ATHLTHUnifiedLibraryScope.allCases, [.athlth, .mine, .favorites])
        XCTAssertNotEqual(
            ATHLTHUnifiedLibraryScope.athlth.title,
            ATHLTHUnifiedLibraryScope.mine.title
        )
    }

    func testExerciseSourceTabsAreDistinctAndKeepMineInSecondPosition() {
        let tabs = ExerciseLibrarySection.allCases
        XCTAssertEqual(tabs.map(\.title).count, 3)
        XCTAssertEqual(tabs.map(\.segmentedIndex), [0, 1, 2])
        XCTAssertEqual(ExerciseLibrarySection.section(forSegmentedIndex: 0), .library)
        XCTAssertEqual(ExerciseLibrarySection.section(forSegmentedIndex: 1), .mine)
        XCTAssertEqual(ExerciseLibrarySection.section(forSegmentedIndex: 2), .marketplace)
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
