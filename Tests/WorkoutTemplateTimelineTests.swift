import Foundation
import XCTest
@testable import ATHLTH

final class WorkoutTemplateTimelineTests: XCTestCase {
    private func exercise(_ title: String) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: title,
            exerciseSlug: "test", distanceMeters: nil,
            repetitions: 8, durationSeconds: nil,
            targetWeightKilograms: 40,
            loadNote: nil, notes: nil, phase: .main
        )
    }

    private func running() -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Run",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 120,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
    }

    private func recovery() -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 2, kind: .rest, title: "Recovery",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 60,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .recovery
        )
    }

    func testThreeSetsInsertRecoveryOnlyBetweenSets() {
        var block = exercise("Squat")
        block.setCount = 3
        block.restBetweenSetsSeconds = 90
        let steps = [block].expandedForExecution()

        XCTAssertEqual(steps.count, 5)
        XCTAssertEqual(steps.map(\.kind), [
            .exercise, .rest, .exercise, .rest, .exercise
        ])
        XCTAssertEqual(steps.filter { $0.kind == .rest }.compactMap(\.durationSeconds), [90, 90])
        XCTAssertEqual(steps.filter { $0.kind == .exercise }.compactMap(\.repetitions), [8, 8, 8])
        XCTAssertEqual(steps.map(\.sequence), [1, 2, 3, 4, 5])
        XCTAssertEqual(Set(steps.map(\.id)).count, steps.count)
    }

    func testSupersetRunsEachExerciseInOrderForEveryRound() {
        let group = UUID()
        var squat = exercise("Squat")
        var pushup = exercise("Push-up")
        squat.groupID = group
        squat.groupKind = .superset
        squat.groupRounds = 3
        pushup.groupID = group
        pushup.groupKind = .superset
        pushup.groupRounds = 3

        let steps = [squat, pushup].expandedForExecution()
        XCTAssertEqual(steps.count, 6)
        XCTAssertEqual(steps.map { $0.title.components(separatedBy: " · ")[0] },
                       ["Squat", "Push-up", "Squat", "Push-up", "Squat", "Push-up"])
        XCTAssertTrue(steps.allSatisfy { $0.groupID == nil })
    }

    func testIntervalRepeatsRunAndRecoveryButSkipsFinalRecovery() {
        let id = UUID()
        var run = running()
        var rest = recovery()
        run.groupID = id
        run.groupKind = .intervals
        run.groupRounds = 4
        rest.groupID = id
        rest.groupKind = .intervals
        rest.groupRounds = 4

        let steps = [run, rest].expandedForExecution()
        XCTAssertEqual(steps.count, 7)
        XCTAssertEqual(steps.filter { $0.kind == .run }.count, 4)
        XCTAssertEqual(steps.filter { $0.kind == .rest }.count, 3)
        XCTAssertEqual(steps.last?.kind, .run)
    }

    func testLegacyRecipeDecodesAndRunsOnce() throws {
        let saved = exercise("Legacy")
        let data = try JSONEncoder().encode(saved)
        let restored = try JSONDecoder().decode(WorkoutTemplateBlock.self, from: data)
        XCTAssertNil(restored.setCount)
        XCTAssertNil(restored.groupID)
        XCTAssertEqual([restored].expandedForExecution().count, 1)
    }

    func testGroupFieldsSurviveEncoding() throws {
        var block = exercise("Bench press")
        block.groupID = UUID()
        block.groupKind = .superset
        block.groupRounds = 4
        let saved = try JSONEncoder().encode(block)
        let restored = try JSONDecoder().decode(WorkoutTemplateBlock.self, from: saved)
        XCTAssertEqual(restored.groupID, block.groupID)
        XCTAssertEqual(restored.groupKind, .superset)
        XCTAssertEqual(restored.groupRounds, 4)
    }
}
