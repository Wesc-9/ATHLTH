import XCTest
@testable import ATHLTH

final class ATHLTHStudioBlockReorderTests: XCTestCase {
    private func step(
        _ title: String, phase: WorkoutPhaseKind = .warmup,
        groupID: UUID? = nil
    ) -> WorkoutTemplateBlock {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: title,
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 60, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: phase
        )
        block.groupID = groupID
        if groupID != nil { block.groupKind = .intervals; block.groupRounds = 4 }
        return block
    }

    func testMoveDownAndBackUpChangesRealExecutionOrder() {
        let a = step("A"), b = step("B"), c = step("C")
        let down = ATHLTHStudioBlockReorder.moving(
            a.editorDragID, to: .warmup, over: b.editorDragID,
            in: [a, b, c]
        )
        XCTAssertEqual(down.map(\.title), ["B", "A", "C"])
        XCTAssertEqual(down.map(\.sequence), [1, 2, 3])
        let up = ATHLTHStudioBlockReorder.moving(
            a.editorDragID, to: .warmup, over: b.editorDragID, in: down
        )
        XCTAssertEqual(up.map(\.title), ["A", "B", "C"])
    }

    func testIntervalsMoveAsGroupWithoutSplitting() {
        let groupID = UUID()
        let a = step("A")
        let effort = step("Effort", groupID: groupID)
        let rest = step("Rest", groupID: groupID)
        let b = step("B")
        let result = ATHLTHStudioBlockReorder.moving(
            rest.editorDragID, to: .warmup, over: b.editorDragID,
            in: [a, effort, rest, b]
        )
        XCTAssertEqual(result.map(\.title), ["A", "B", "Effort", "Rest"])
        XCTAssertEqual(result[2].groupID, groupID)
        XCTAssertEqual(result[3].groupID, groupID)
        XCTAssertEqual(result.map(\.sequence), [1, 2, 3, 4])
    }

    func testMoveToAnotherPhasePreservesDataAndIDs() {
        var run = step("Running", phase: .warmup)
        run.targetHeartRateZone = 3
        let main = step("Main", phase: .main)
        let result = ATHLTHStudioBlockReorder.moving(
            run.editorDragID, to: .main, over: nil, in: [run, main]
        )
        XCTAssertEqual(result.map(\.title), ["Main", "Running"])
        XCTAssertEqual(result[1].resolvedPhase, .main)
        XCTAssertEqual(result[1].editorDragID, run.editorDragID)
        XCTAssertEqual(result[1].targetHeartRateZone, 3)
    }

    func testDroppedOnOwnGroupDoesNotSplitIt() {
        let id = UUID()
        let a = step("A", groupID: id), b = step("B", groupID: id)
        let source = [a, b]
        XCTAssertEqual(
            ATHLTHStudioBlockReorder.moving(
                a.editorDragID, to: .warmup, over: b.editorDragID, in: source
            ).map(\.title),
            ["A", "B"]
        )
    }

    func testSuggestedNameUsesDurationButDoesNotStoreText() {
        let run = step("Running")
        let name = ATHLTHWorkoutNameSuggestion.suggested(
            activity: .running, blocks: [run], durationMinutes: 20,
            routeTitle: nil
        )
        XCTAssertTrue(name.contains("20 min"))
        XCTAssertEqual(ATHLTHWorkoutNameSuggestion.displayStepTitle(run),
                       ATHLTHLocalization.choose(english: "Running", norwegian: "Løping"))
    }
}
