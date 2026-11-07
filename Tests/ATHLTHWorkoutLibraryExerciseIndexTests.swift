import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHWorkoutLibraryExerciseIndexTests: XCTestCase {
    private func block(
        _ kind: WorkoutTemplateBlockKind,
        _ title: String,
        phase: WorkoutPhaseKind,
        slug: String? = nil
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: kind, title: title,
            exerciseSlug: slug, distanceMeters: nil, repetitions: nil,
            durationSeconds: nil, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: phase
        )
    }

    private var sample: [WorkoutTemplateBlock] {
        [
            block(.note, "Forbered økten", phase: .warmup),
            block(.exercise, "Knebøy", phase: .main, slug: "squat"),
            block(.exercise, "Benkpress", phase: .main, slug: "bench"),
            block(.rest, "Pause", phase: .recovery),
            block(.exercise, "Nedtrekk", phase: .main, slug: "pulldown"),
            block(.note, "Takk for i dag", phase: .cooldown)
        ]
    }

    func testCompactWorkoutCardPrioritizesMainExercisesAndCountsOverflow() {
        let result = ATHLTHWorkoutLibraryExerciseIndex.preview(
            blocks: sample, limit: 2
        )
        XCTAssertEqual(result.titles, ["Knebøy", "Benkpress"])
        XCTAssertEqual(result.remaining, 1)
    }

    func testExactExerciseFilterDoesNotMatchUnrelatedProgram() {
        XCTAssertTrue(ATHLTHWorkoutLibraryExerciseIndex.containsExercise(
            "Knebøy", in: sample
        ))
        XCTAssertTrue(ATHLTHWorkoutLibraryExerciseIndex.containsExercise(
            "squat", in: sample
        ))
        XCTAssertFalse(ATHLTHWorkoutLibraryExerciseIndex.containsExercise(
            "Skråbenk med manualer", in: sample
        ))
        XCTAssertFalse(ATHLTHWorkoutLibraryExerciseIndex.containsExercise(
            "Pause", in: sample
        ))
    }

    func testExerciseSearchRespectsNorwegianCaseAndDiacritics() {
        XCTAssertTrue(ATHLTHWorkoutLibraryExerciseIndex.containsExercise(
            "kneboy", in: sample
        ))
        XCTAssertEqual(
            ATHLTHWorkoutLibraryExerciseIndex.normalize("  KNEBØY  "),
            "kneboy"
        )
    }

    func testStrengthDurationFiltersDoNotIncludeUnknownLengths() {
        XCTAssertTrue(ATHLTHWorkoutDiscoveryFilter.Duration.medium.matches(minutes: 40))
        XCTAssertFalse(ATHLTHWorkoutDiscoveryFilter.Duration.medium.matches(minutes: nil))
    }
}
