import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHStrengthGroupedSetTests: XCTestCase {
    private func exercise(
        _ reps: Int = 10, weight: Double = 25, sets: Int = 3
    ) -> WorkoutTemplateBlock {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Barbell Curl",
            exerciseSlug: "barbell-curl", distanceMeters: nil,
            repetitions: reps, durationSeconds: nil,
            targetWeightKilograms: weight, loadNote: nil,
            notes: nil, phase: .main
        )
        block.setCount = sets
        block.restBetweenSetsSeconds = 60
        return block
    }

    func testOneParentCreatesIndividualExecutionSetsAndPauses() {
        var block = exercise()
        var targets = ATHLTHWorkoutSetExpansion.targets(for: block)
        targets[0].repetitions = 12
        targets[1].weightKilograms = 30
        targets[2].repetitions = 8
        block.individualSetTargets = targets

        let recipe = [block]
        XCTAssertEqual(recipe.count, 1, "The editor stores one parent exercise")
        let playback = recipe.expandedForExecution()
        XCTAssertEqual(playback.map(\.kind),
                       [.exercise, .rest, .exercise, .rest, .exercise])
        XCTAssertEqual(playback.filter { $0.kind == .exercise }.map(\.repetitions),
                       [12, 10, 8])
        XCTAssertEqual(playback.filter { $0.kind == .exercise }
                        .map(\.targetWeightKilograms), [25, 30, 25])
        XCTAssertEqual(playback.filter { $0.kind == .rest }.map(\.durationSeconds),
                       [60, 60])
    }

    func testIncreasingNumberOfSetsPreservesIndividualTargets() {
        var block = exercise()
        var targets = ATHLTHWorkoutSetExpansion.targets(for: block)
        targets[0].repetitions = 6
        block.individualSetTargets = targets
        block.setCount = 4
        let expanded = ATHLTHWorkoutSetExpansion.targets(for: block)
        XCTAssertEqual(expanded.count, 4)
        XCTAssertEqual(expanded[0].repetitions, 6)
        XCTAssertEqual(expanded[3].repetitions, 10)
    }

    func testRenumberAndCodableRoundTripKeepIndividualTargets() throws {
        var block = exercise()
        var targets = ATHLTHWorkoutSetExpansion.targets(for: block)
        targets[1].weightKilograms = 32.5
        block.individualSetTargets = targets

        let moved = ATHLTHWorkoutPhasePlacement.renumbered(block, sequence: 2)
        let decoded = try JSONDecoder().decode(
            WorkoutTemplateBlock.self,
            from: JSONEncoder().encode(moved)
        )
        XCTAssertEqual(decoded.sequence, 2)
        XCTAssertEqual(decoded.individualSetTargets?[1].weightKilograms, 32.5)
        XCTAssertEqual([decoded].expandedForExecution().count, 5)
    }

    func testLegacySplitSetsCollapseOnlyWhenRestMarkerMatches() {
        var base = exercise()
        base.setCount = nil
        base.restBetweenSetsSeconds = nil
        var second = ATHLTHWorkoutPhasePlacement.renumbered(base, sequence: 3)
        second.repetitions = 8
        var rest = WorkoutTemplateBlock(
            sequence: 2, kind: .rest, title: "Mellom sett",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 60,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .recovery
        )
        rest.editorDragID = UUID()
        let converted = ATHLTHWorkoutSetExpansion.collapsingLegacySets(
            in: [base, rest, second]
        )
        XCTAssertEqual(converted.count, 1)
        XCTAssertEqual(converted[0].setCount, 2)
        XCTAssertEqual(converted[0].individualSetTargets?.map(\.repetitions), [10, 8])

        var unrelatedRest = rest
        unrelatedRest.title = "Pause"
        XCTAssertEqual(ATHLTHWorkoutSetExpansion.collapsingLegacySets(
            in: [base, unrelatedRest, second]
        ).count, 3)
    }
}
