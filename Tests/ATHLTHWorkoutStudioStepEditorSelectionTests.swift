import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutStudioStepEditorSelectionTests: XCTestCase {
    private func step(_ sequence: Int, title: String) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: sequence,
            kind: .run,
            title: title,
            exerciseSlug: nil,
            distanceMeters: 1_000,
            repetitions: nil,
            durationSeconds: nil,
            targetWeightKilograms: nil,
            loadNote: nil,
            notes: nil,
            phase: .main
        )
    }

    func testSelectedStepResolvesBeforeAnySceneRefresh() {
        let blocks = [step(1, title: "Warmup"), step(2, title: "Tempo")]
        let selected = ATHLTHWorkoutStudioStepEditorSelection(
            blockID: blocks[1].editorDragID, blocks: blocks
        )
        XCTAssertNotNil(selected)
        XCTAssertEqual(selected?.index(in: blocks), 1)
    }

    func testSelectionSurvivesDraftDecodeThatRegeneratesEditorDragIDs() throws {
        let original = [step(1, title: "Warmup"), step(2, title: "Tempo")]
        let selected = try XCTUnwrap(ATHLTHWorkoutStudioStepEditorSelection(
            blockID: original[1].editorDragID, blocks: original
        ))
        let serialized = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode([WorkoutTemplateBlock].self, from: serialized)

        XCTAssertNotEqual(original[1].editorDragID, restored[1].editorDragID)
        XCTAssertEqual(selected.index(in: restored), 1)
        XCTAssertNil(selected.index(in: []))
    }

    func testSelectionTracksStepAfterReorderingAndIgnoresMissingSteps() throws {
        let original = [step(1, title: "Warmup"), step(2, title: "Tempo")]
        let selected = try XCTUnwrap(ATHLTHWorkoutStudioStepEditorSelection(
            blockID: original[1].editorDragID, blocks: original
        ))
        XCTAssertEqual(selected.index(in: Array(original.reversed())), 0)
        XCTAssertNil(selected.index(in: [original[0]]))
        XCTAssertNil(ATHLTHWorkoutStudioStepEditorSelection(
            blockID: UUID(), blocks: original
        ))
    }
}
