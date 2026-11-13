import XCTest
@testable import ATHLTH

/// Simple/Advanced are two projections of the same real workout timeline.
/// Neither Plan Studio nor Quick Train may rewrite a recipe for presentation.
final class ATHLTHSimpleWorkoutOutlineTests: XCTestCase {
    private func block(
        _ title: String,
        kind: WorkoutTemplateBlockKind = .run,
        phase: WorkoutPhaseKind,
        index: Int,
        duration: TimeInterval = 60,
        pace: Double? = nil
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: index, kind: kind, title: title,
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: duration, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: phase,
            targetPaceSecondsPerKilometer: pace
        )
    }

    func testOneMinuteIntervalsCompactIntoSingleSimpleMainGroup() {
        var recipe = [
            block("Warm up", phase: .warmup, index: 1, duration: 600)
        ]
        for index in 1...12 {
            recipe.append(block(
                "1min VO2-maks", phase: .main,
                index: recipe.count + 1
            ))
            if index < 12 {
                recipe.append(block(
                    "Active recovery", kind: .rest,
                    phase: .recovery, index: recipe.count + 1
                ))
            }
        }
        recipe.append(block(
            "Cool down", phase: .cooldown,
            index: recipe.count + 1, duration: 480
        ))
        let untouched = recipe
        let stages = ATHLTHSimpleWorkoutOutline.stages(for: recipe)
        XCTAssertEqual(stages.count, 3)
        XCTAssertEqual(stages[1].phase, .main)
        XCTAssertEqual(stages[1].sourceStepCount, 23)
        XCTAssertEqual(stages[1].items.count, 1)
        XCTAssertEqual(stages[1].items[0].repetitions, 12)
        XCTAssertEqual(stages[1].items[0].representedSteps, 23)
        XCTAssertTrue(stages[1].items[0].title.contains("12 ×"))
        XCTAssertEqual(stages[1].plannedSeconds, 23 * 60)
        XCTAssertEqual(recipe, untouched)
    }

    func testPersonalTargetsMustNotBeHiddenByGroupingDistinctRepeats() {
        let recipe = [
            block("VO2", phase: .main, index: 1, pace: 300),
            block("Recovery", kind: .rest, phase: .recovery, index: 2),
            block("VO2", phase: .main, index: 3, pace: 275),
            block("Recovery", kind: .rest, phase: .recovery, index: 4)
        ]
        let items = ATHLTHSimpleWorkoutOutline.stages(for: recipe)[0].items
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.representedSteps), [2, 2])
    }

    func testCompactModeNeverChangesSourceOrderOrSequence() {
        let recipe = [
            block("Warm up", phase: .warmup, index: 1, duration: 300),
            block("Work", phase: .main, index: 2, duration: 120),
            block("Recovery", kind: .rest, phase: .recovery, index: 3),
            block("Cool down", phase: .cooldown, index: 4, duration: 300)
        ]
        let before = recipe.map(\.sequence)
        _ = ATHLTHSimpleWorkoutOutline.stages(for: recipe)
        XCTAssertEqual(recipe.map(\.sequence), before)
        XCTAssertEqual(recipe.count, 4)
    }
}
