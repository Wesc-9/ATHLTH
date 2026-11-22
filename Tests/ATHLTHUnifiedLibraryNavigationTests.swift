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

    func testAllWorkoutSheetHasNineActivitiesInRequestedGridOrder() {
        let categories = ATHLTHTrainAllWorkoutCategoriesSheet.Category.allCases
        XCTAssertEqual(categories.map(\.rawValue), [
            "freeTraining", "walking", "running",
            "strength", "cycling", "swimming",
            "yoga", "meditation", "custom"
        ])
    }

    func testUnavailableWorkoutsStayVisibleButDisabled() {
        let categories = ATHLTHTrainAllWorkoutCategoriesSheet.Category.allCases
        let enabled = categories.filter(\.isAvailable).map(\.rawValue)
        let disabled = categories.filter { !$0.isAvailable }.map(\.rawValue)

        XCTAssertEqual(enabled, [
            "freeTraining", "walking", "running", "strength", "custom"
        ])
        XCTAssertEqual(disabled, [
            "cycling", "swimming", "yoga", "meditation"
        ])
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
