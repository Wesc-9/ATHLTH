import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class StrengthAIExerciseSelectionPolicyTests: XCTestCase {
    private func entry(
        _ name: String,
        source: ExerciseLibrarySource,
        focus: String = "Chest",
        equipment: [String] = ["Dumbbell"]
    ) -> ExerciseLibraryEntry {
        let exercise = Exercise(
            id: UUID(),
            origin: .publicCatalog,
            ownerID: nil,
            name: name,
            instructions: [],
            primaryMuscles: [focus],
            secondaryMuscles: [],
            equipment: equipment,
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: true
        )
        return ExerciseLibraryEntry(
            id: exercise.id,
            exercise: exercise,
            source: source,
            sourceIdentifier: nil,
            summary: nil,
            tips: [],
            category: "Strength",
            difficulty: nil,
            bodyPart: focus,
            imageStartURL: nil,
            imagePeakURL: nil
        )
    }

    private func suggestion(_ id: UUID) -> StrengthAIExerciseSuggestion {
        StrengthAIExerciseSuggestion(
            exerciseID: id,
            sets: 3,
            reps: 8,
            restSeconds: 90,
            targetRPE: nil,
            reason: ""
        )
    }

    func testMineOnlyIncludesCustomExercisesAndRespectsFilters() {
        let catalog = entry("Catalog chest", source: .athlthCatalog)
        let own = entry("My chest", source: .custom)
        let back = entry("My back", source: .custom, focus: "Back")
        let barbell = entry("My barbell", source: .custom, equipment: ["Barbell"])
        let all = [catalog, own, back, barbell]

        let filtered = StrengthAIExerciseSelectionPolicy.available(
            from: all, excluding: [],
            source: .mine, focus: "Chest", equipment: "Dumbbell"
        )
        XCTAssertEqual(filtered.map(\.id), [own.id])
    }

    func testEntireLibraryIncludesCatalogAndMineButExcludesExistingWorkout() {
        let catalog = entry("Catalog", source: .athlthCatalog)
        let own = entry("Mine", source: .custom)
        let filtered = StrengthAIExerciseSelectionPolicy.available(
            from: [catalog, own],
            excluding: [own.id], source: .library, focus: nil, equipment: nil
        )
        XCTAssertEqual(filtered.map(\.id), [catalog.id])
    }

    func testOnlyExactUniqueAllowedExerciseIDsCanBeApplied() {
        let allowed = UUID()
        let second = UUID()
        let invented = UUID()
        XCTAssertTrue(StrengthAIExerciseSelectionPolicy.verified(
            [suggestion(allowed), suggestion(second)],
            allowedIDs: [allowed, second],
            existingIDs: [],
            requiredCount: 2
        ))
        XCTAssertFalse(StrengthAIExerciseSelectionPolicy.verified(
            [suggestion(allowed), suggestion(invented)],
            allowedIDs: [allowed, second],
            existingIDs: [],
            requiredCount: 2
        ))
        XCTAssertFalse(StrengthAIExerciseSelectionPolicy.verified(
            [suggestion(allowed), suggestion(allowed)],
            allowedIDs: [allowed, second],
            existingIDs: [],
            requiredCount: 2
        ))
        XCTAssertFalse(StrengthAIExerciseSelectionPolicy.verified(
            [suggestion(allowed)],
            allowedIDs: [allowed, second],
            existingIDs: [allowed],
            requiredCount: 1
        ))
        XCTAssertFalse(StrengthAIExerciseSelectionPolicy.verified(
            [], allowedIDs: [allowed], existingIDs: [], requiredCount: 0
        ))
    }
}
