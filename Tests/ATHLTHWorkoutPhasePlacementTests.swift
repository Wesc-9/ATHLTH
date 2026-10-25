import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutPhasePlacementTests: XCTestCase {
    private func block(
        _ title: String,
        phase: WorkoutPhaseKind,
        group: UUID? = nil
    ) -> WorkoutTemplateBlock {
        var result = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: title, exerciseSlug: nil,
            distanceMeters: nil, repetitions: nil, durationSeconds: 600,
            targetWeightKilograms: nil, loadNote: nil, notes: nil,
            phase: phase
        )
        result.groupID = group
        return result
    }

    func testWarmupAddedBeforeMainAndCooldown() {
        let items = [block("Strength", phase: .main),
                     block("Cool down", phase: .cooldown)]
        XCTAssertEqual(ATHLTHWorkoutPhasePlacement.insertionIndex(
            for: .warmup, in: items
        ), 0)
    }

    func testMainAddedBeforeCooldown() {
        let items = [block("Warm up", phase: .warmup),
                     block("Cool down", phase: .cooldown)]
        XCTAssertEqual(ATHLTHWorkoutPhasePlacement.insertionIndex(
            for: .main, in: items
        ), 1)
    }

    func testAdditionalWarmupStaysAfterExistingWarmup() {
        let items = [block("First", phase: .warmup),
                     block("Main", phase: .main)]
        XCTAssertEqual(ATHLTHWorkoutPhasePlacement.insertionIndex(
            for: .warmup, in: items
        ), 1)
    }

    func testGroupBoundaryIsNeverSplit() {
        let id = UUID()
        let items = [block("Work", phase: .main, group: id),
                     block("Rest", phase: .cooldown, group: id),
                     block("Finish", phase: .cooldown)]
        XCTAssertEqual(ATHLTHWorkoutPhasePlacement.insertionIndex(
            for: .main, in: items
        ), 0)
    }

    func testCooldownAppendsAfterOtherPhases() {
        let items = [block("Main", phase: .main)]
        XCTAssertEqual(ATHLTHWorkoutPhasePlacement.insertionIndex(
            for: .cooldown, in: items
        ), items.count)
    }
}
