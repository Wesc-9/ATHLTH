import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPremiumStrengthSessionsTests: XCTestCase {
    private let focuses = [
        "chest", "back", "legs", "shoulders", "arms",
        "glutes", "fullbody", "core", "home"
    ]
    private let levels = ["Beginner", "Intermediate", "Advanced", "Expert"]

    @MainActor
    func testEachMuscleGroupHasExactlyFourDistinctTrainingLevels() {
        XCTAssertEqual(ATHLTHPremiumStrengthSessions.recipes.count, 36)
        for focus in focuses {
            let recipes = ATHLTHPremiumStrengthSessions.recipes(for: focus)
            XCTAssertEqual(recipes.count, 4, focus)
            XCTAssertEqual(Set(recipes.map(\.level)), Set(levels), focus)
            XCTAssertEqual(Set(recipes.map(\.id)).count, 4, focus)
        }
        XCTAssertEqual(
            ATHLTHPremiumStrengthSessions.recipes.reduce(0) { $0 + $1.moves.count },
            157
        )
    }

    @MainActor
    func testNoUserWorkingWeightIsAssignedInAnySession() {
        for recipe in ATHLTHPremiumStrengthSessions.recipes {
            let blocks = ATHLTHPremiumStrengthSessions.blocks(for: recipe)
            XCTAssertTrue(blocks.allSatisfy { $0.targetWeightKilograms == nil },
                          "Weight set by template: \(recipe.titleEN)")
            XCTAssertTrue(blocks.allSatisfy { $0.loadNote == nil })
            XCTAssertEqual(blocks.first?.resolvedPhase, .warmup)
            XCTAssertEqual(blocks.filter { $0.kind == .exercise }.count,
                           recipe.moves.count)
            XCTAssertTrue(blocks.dropFirst().allSatisfy {
                $0.targetEffortRPE != nil
            })
        }
    }

    @MainActor
    func testRepRangesRIRAndRestArePreservedWithoutSettingLoad() {
        for recipe in ATHLTHPremiumStrengthSessions.recipes {
            let blocks = ATHLTHPremiumStrengthSessions.blocks(for: recipe)
                .filter { $0.kind == .exercise }
            for (block, move) in zip(blocks, recipe.moves) {
                XCTAssertEqual(block.setCount, move.sets)
                XCTAssertEqual(block.repetitions, move.repsMin)
                XCTAssertEqual(block.durationSeconds,
                               move.durationSeconds.map(TimeInterval.init))
                XCTAssertEqual(block.restBetweenSetsSeconds,
                               TimeInterval(move.restSeconds))
                XCTAssertEqual(block.targetEffortRPE, 10 - move.rir)
                XCTAssertNil(block.targetWeightKilograms)
                XCTAssertTrue(block.notes?.contains("RIR") == true)
            }
        }
    }

    @MainActor
    func testChestBeginnerAndExpertAreGenuinelyDifferent() throws {
        let chest = ATHLTHPremiumStrengthSessions.recipes(for: "chest")
        let beginner = try XCTUnwrap(chest.first { $0.level == "Beginner" })
        let expert = try XCTUnwrap(chest.first { $0.level == "Expert" })
        XCTAssertEqual(beginner.moves.count, 3)
        XCTAssertEqual(expert.moves.count, 5)
        XCTAssertLessThan(beginner.moves.reduce(0) { $0 + $1.sets },
                          expert.moves.reduce(0) { $0 + $1.sets })
        XCTAssertGreaterThan(expert.estimatedDurationMinutes,
                             beginner.estimatedDurationMinutes)
        XCTAssertNil(
            ATHLTHPremiumStrengthSessions.blocks(for: expert)
                .first(where: { $0.kind == .exercise })?.targetWeightKilograms
        )
    }

    @MainActor
    func testWorkoutsAreAvailableOfflineAndTaggedForFiltering() {
        let entries = ATHLTHPremiumStrengthSessions.entries
        XCTAssertEqual(entries.count, 36)
        XCTAssertEqual(Set(entries.map(\.slug)).count, 36)
        XCTAssertEqual(Set(entries.map(\.id)).count, 36)
        XCTAssertTrue(entries.allSatisfy { $0.category == "strength" })
        XCTAssertTrue(entries.allSatisfy { $0.tags.contains("premium-strength") })
        for entry in entries {
            let workout = entry.plannedSession()
            XCTAssertTrue(workout.resolvedWorkoutBlocks.contains {
                $0.kind == .exercise
            })
            XCTAssertTrue(workout.resolvedWorkoutBlocks.allSatisfy {
                $0.targetWeightKilograms == nil
            })
        }
    }
}
