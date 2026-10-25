import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutPhaseRelocationTests: XCTestCase {
    private func step(
        _ title: String,
        kind: WorkoutTemplateBlockKind = .run,
        phase: WorkoutPhaseKind,
        sequence: Int,
        groupID: UUID? = nil,
        groupKind: WorkoutTemplateGroupKind? = nil,
        rounds: Int? = nil
    ) -> WorkoutTemplateBlock {
        var result = WorkoutTemplateBlock(
            sequence: sequence, kind: kind, title: title,
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 60, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: phase
        )
        result.groupID = groupID
        result.groupKind = groupKind
        result.groupRounds = rounds
        return result
    }

    func testMovingIntervalTransfersEffortsAndRestWithoutSplittingFourRounds() {
        let id = UUID()
        let warmup = step("Warmup", phase: .warmup, sequence: 1)
        let effort = step("Effort", phase: .main, sequence: 2,
                          groupID: id, groupKind: .intervals, rounds: 4)
        let recovery = step("Recovery", kind: .rest, phase: .main,
                            sequence: 3, groupID: id,
                            groupKind: .intervals, rounds: 4)
        let strength = step("Squat", kind: .exercise,
                            phase: .main, sequence: 4)
        let cooldown = step("Cooldown", phase: .cooldown, sequence: 5)

        let result = ATHLTHWorkoutPhasePlacement.relocatingSelection(
            at: 2, to: .warmup,
            in: [warmup, effort, recovery, strength, cooldown]
        )
        XCTAssertEqual(result.map(\.title),
                       ["Warmup", "Effort", "Recovery", "Squat", "Cooldown"])
        XCTAssertEqual(result.map(\.sequence), [1, 2, 3, 4, 5])
        XCTAssertEqual(result[1].resolvedPhase, .warmup)
        XCTAssertEqual(result[2].resolvedPhase, .warmup)
        XCTAssertEqual(result[1].groupID, id)
        XCTAssertEqual(result[2].groupID, id)
        let expanded = result.expandedForExecution()
        XCTAssertEqual(expanded.filter { $0.title == "Effort" }.count, 4)
        XCTAssertEqual(expanded.filter { $0.title == "Recovery" }.count, 3)
    }

    func testSingleStrengthExerciseMovesAfterMainBeforeCooldown() {
        let source = [
            step("Warmup", phase: .warmup, sequence: 1),
            step("Squat", kind: .exercise, phase: .warmup, sequence: 2),
            step("Run", phase: .main, sequence: 3),
            step("Cooldown", phase: .cooldown, sequence: 4)
        ]
        let result = ATHLTHWorkoutPhasePlacement.relocatingSelection(
            at: 1, to: .main, in: source
        )
        XCTAssertEqual(result.map(\.title),
                       ["Warmup", "Run", "Squat", "Cooldown"])
        XCTAssertEqual(result[2].resolvedPhase, .main)
        XCTAssertEqual(result.map(\.sequence), [1, 2, 3, 4])
    }

    func testSupersetMovesAsOneBlockAndKeepsRelativeExerciseOrder() {
        let id = UUID()
        let source = [
            step("Run", phase: .warmup, sequence: 1),
            step("A", kind: .exercise, phase: .main, sequence: 2,
                 groupID: id, groupKind: .superset, rounds: 3),
            step("B", kind: .exercise, phase: .main, sequence: 3,
                 groupID: id, groupKind: .superset, rounds: 3),
            step("Cooldown", phase: .cooldown, sequence: 4)
        ]
        let result = ATHLTHWorkoutPhasePlacement.relocatingSelection(
            at: 2, to: .cooldown, in: source
        )
        XCTAssertEqual(result.map(\.title), ["Run", "Cooldown", "A", "B"])
        XCTAssertEqual(result[2].groupID, id)
        XCTAssertEqual(result[3].groupID, id)
        XCTAssertEqual(result[2].resolvedPhase, .cooldown)
        XCTAssertEqual(result[3].resolvedPhase, .cooldown)
    }

    func testNoOpForSamePhaseOrInvalidIndex() {
        let source = [step("Jog", phase: .warmup, sequence: 1)]
        XCTAssertEqual(
            ATHLTHWorkoutPhasePlacement.relocatingSelection(
                at: 0, to: .warmup, in: source),
            source
        )
        XCTAssertEqual(
            ATHLTHWorkoutPhasePlacement.relocatingSelection(
                at: 5, to: .main, in: source),
            source
        )
    }
}
