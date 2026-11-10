import XCTest
@testable import ATHLTH

final class SimpleExerciseMuscleFilterTests: XCTestCase {
    func testLibrarySegmentedTabsHaveStableDistinctIndices() {
        XCTAssertEqual(
            ExerciseLibrarySection.allCases.map(\.segmentedIndex),
            [0, 1, 2]
        )
        for section in ExerciseLibrarySection.allCases {
            XCTAssertEqual(
                ExerciseLibrarySection.section(
                    forSegmentedIndex: section.segmentedIndex
                ),
                section
            )
        }
        XCTAssertEqual(
            ExerciseLibrarySection.section(forSegmentedIndex: -1),
            .library
        )
        XCTAssertEqual(
            ExerciseLibrarySection.section(forSegmentedIndex: 999),
            .library
        )
    }

    @MainActor
    func testOnlyNineMajorGroupsShown() {
        let library = ExerciseLibraryStore()
        XCTAssertEqual(library.bodyParts, [
            "Chest", "Back", "Shoulders", "Biceps", "Triceps",
            "Core", "Glutes", "Legs", "Calves"
        ])
    }

    @MainActor
    func testAnatomicalGroupsAreMapped() {
        let examples: [(String, String)] = [
            ("Pectoralis Major", "Chest"),
            ("Lower Back", "Back"),
            ("Latissimus Dorsi", "Back"),
            ("Rhomboids", "Back"),
            ("Anterior Deltoid", "Shoulders"),
            ("Brachialis", "Biceps"),
            ("Brachioradialis", "Biceps"),
            ("Triceps Brachii", "Triceps"),
            ("Rectus Abdominis", "Core"),
            ("Obliques", "Core"),
            ("Gluteus Maximus", "Glutes"),
            ("Abductors", "Glutes"),
            ("Adductors", "Legs"),
            ("Quadriceps", "Legs"),
            ("Hamstrings", "Legs"),
            ("Upper Legs", "Legs"),
            ("Gastrocnemius", "Calves")
        ]
        for (input, expected) in examples {
            XCTAssertEqual(
                ExerciseLibraryStore.canonicalMuscleFilter(input),
                expected
            )
        }
    }

    @MainActor
    func testEachMuscleFilterFindsExercises() {
        let library = ExerciseLibraryStore()
        for filter in library.bodyParts {
            XCTAssertFalse(
                library.search(query: "", bodyPart: filter).isEmpty,
                "No exercises for \(filter)"
            )
        }
    }
    func testEachVisibleMuscleGroupHasDistinctIcon() {
        let groups = [
            "Back", "Chest", "Shoulders", "Biceps", "Triceps",
            "Core", "Glutes", "Legs", "Calves"
        ]
        let symbols = groups.map(ATHLTHExerciseMuscleFilterPresentation.icon(for:))
        XCTAssertEqual(Set(symbols).count, groups.count,
            "Every muscle chip must be visually distinguishable at a glance")
        XCTAssertEqual(ATHLTHExerciseMuscleFilterPresentation.icon(for: "Back"),
                       "figure.rower")
    }

    func testFreeStrengthIsOnlyAnExercisePickerShortcut() {
        XCTAssertFalse(ATHLTHFreeStrengthLibraryPresentation.showsShortcut(
            isSelectingExercise: false))
        XCTAssertTrue(ATHLTHFreeStrengthLibraryPresentation.showsShortcut(
            isSelectingExercise: true))
        XCTAssertFalse(ATHLTHFreeStrengthLibraryPresentation.includesInExerciseResults(
            sourceIdentifier: "athlth-native-free-strength-training"))
        XCTAssertTrue(ATHLTHFreeStrengthLibraryPresentation.includesInExerciseResults(
            sourceIdentifier: "repdb-bench-press"))
        XCTAssertTrue(ATHLTHFreeStrengthLibraryPresentation.includesInExerciseResults(
            sourceIdentifier: nil))
    }

}
