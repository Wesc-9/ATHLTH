import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutPhaseOutlineTests: XCTestCase {
    private func block(_ index: Int, phase: WorkoutPhaseKind) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: index, kind: .run, title: "Part \(index)",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 60, targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: phase
        )
    }

    func testRecoveryDisplaysUnderPreviousMainPhaseWithoutChangingTheRecipe() {
        let recipe = [
            block(1, phase: .warmup),
            block(2, phase: .main),
            block(3, phase: .recovery),
            block(4, phase: .main),
            block(5, phase: .cooldown)
        ]
        let display = ATHLTHWorkoutPhaseOutline.sections(for: recipe)
        XCTAssertEqual(display.map(\.phase), [.warmup, .main, .cooldown])
        XCTAssertEqual(display.map(\.indices), [[0], [1, 2, 3], [4]])
        XCTAssertEqual(recipe[2].resolvedPhase, .recovery)
    }

    func testLongIntervalRecipesGroupEveryPartOnceInOrder() {
        var recipe = [block(1, phase: .warmup)]
        for i in 0..<100 {
            recipe.append(block(i * 2 + 2, phase: .main))
            recipe.append(block(i * 2 + 3, phase: .recovery))
        }
        recipe.append(block(202, phase: .cooldown))
        let display = ATHLTHWorkoutPhaseOutline.sections(for: recipe)
        XCTAssertEqual(display.flatMap(\.indices), Array(recipe.indices))
        XCTAssertEqual(display[1].indices.count, 200)
    }
}
