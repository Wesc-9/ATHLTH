import XCTest
@testable import ATHLTH

final class SimpleExerciseMuscleFilterTests: XCTestCase {
    @MainActor
    func testOnlyNineMajorGroupsShown() {
        let library = ExerciseLibraryStore()
        XCTAssertEqual(library.bodyParts, [
            "Chest", "Back", "Shoulders", "Biceps", "Triceps",
            "Core", "Glutes", "Legs", "Calves"
        ])
    }

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
}
