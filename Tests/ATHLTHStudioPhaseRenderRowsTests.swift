import XCTest
@testable import ATHLTH

final class ATHLTHStudioPhaseRenderRowsTests: XCTestCase {
    private func block(
        _ title: String,
        kind: WorkoutTemplateBlockKind = .exercise,
        group: UUID? = nil,
        groupKind: WorkoutBlockGroupKind? = nil
    ) -> WorkoutTemplateBlock {
        var result = WorkoutTemplateBlock(
            sequence: 1,
            kind: kind,
            title: title,
            exerciseSlug: kind == .exercise ? title : nil,
            distanceMeters: nil,
            repetitions: kind == .exercise ? 8 : nil,
            durationSeconds: kind == .rest ? 90 : 45,
            targetWeightKilograms: nil,
            loadNote: nil,
            notes: nil,
            phase: kind == .rest ? .recovery : .main
        )
        result.groupID = group
        result.groupKind = groupKind
        result.groupRounds = groupKind == .intervals ? 1 : 3
        return result
    }

    func testThirtyFiveStepWorkoutRendersInSourceOrder() {
        let original = (0..<35).map { index in
            block("Exercise \(index)", kind: index.isMultiple(of: 3) ? .rest : .exercise)
        }
        let rows = ATHLTHStudioPhaseRenderRows.make(from: original)
        XCTAssertEqual(rows.count, 35)
        XCTAssertEqual(rows.map(\.id), original.map(\.editorDragID))
        XCTAssertEqual(rows.map(\.position), Array(0..<35))
        XCTAssertTrue(rows.allSatisfy { $0.kind == .step })
    }

    func testStrengthAndIntervalGroupsCreateOneDisplayCardEach() {
        let strengthID = UUID()
        let intervalID = UUID()
        let strength = [
            block("Squat", group: strengthID, groupKind: .superset),
            block("Lunge", group: strengthID, groupKind: .superset),
            block("Calf Raise", group: strengthID, groupKind: .superset)
        ]
        let intervals = [
            block("Run 1", kind: .run, group: intervalID, groupKind: .intervals),
            block("Recovery 1", kind: .rest, group: intervalID, groupKind: .intervals),
            block("Run 2", kind: .run, group: intervalID, groupKind: .intervals),
            block("Recovery 2", kind: .rest, group: intervalID, groupKind: .intervals)
        ]
        let tail = [block("Other"), block("Rest", kind: .rest)]
        let all = strength + intervals + tail
        let rows = ATHLTHStudioPhaseRenderRows.make(from: all)

        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.map(\.position), [0, 3, 7, 8])
        XCTAssertEqual(rows[0].kind, .strengthGroup(strengthID))
        XCTAssertEqual(rows[1].kind, .intervalGroup(intervalID))
        XCTAssertEqual(rows[2].kind, .step)
        XCTAssertEqual(rows[3].kind, .step)
        XCTAssertEqual(all.count, 9, "The executable source must not be altered")
    }

    func testStandaloneSetEditorPreservesSingleSourceBlock() {
        var exercise = block("Back Extension")
        exercise.setCount = 3
        exercise.restBetweenSetsSeconds = 90
        let rows = ATHLTHStudioPhaseRenderRows.make(
            from: [exercise, block("Pause", kind: .rest)]
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].kind, .strengthSets)
        XCTAssertEqual(rows[1].kind, .step)
        XCTAssertEqual(rows[0].block.setCount, 3)
    }

    func testIncompleteIntervalKeepsAllIndividuallyEditableSteps() {
        let group = UUID()
        let steps = [
            block("Run 1", kind: .run, group: group, groupKind: .intervals),
            block("Run 2", kind: .run, group: group, groupKind: .intervals)
        ]
        let rows = ATHLTHStudioPhaseRenderRows.make(from: steps)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.kind), [.step, .step])
    }
}
