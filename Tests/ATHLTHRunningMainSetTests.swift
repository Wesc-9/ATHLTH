import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHRunningMainSetTests: XCTestCase {
    @MainActor
    func testRunningPickerPresetsContainOnlyRunningAndRecovery() {
        for preset in ATHLTHRunningExercisePreset.allCases {
            let blocks = preset.blocks(in: .main)
            XCTAssertTrue(blocks.contains(where: { $0.kind == .run }),
                          "\(preset.id) should have a running step")
            XCTAssertTrue(blocks.allSatisfy {
                ($0.kind == .run && $0.cardioActivity == .running) ||
                $0.kind == .rest
            }, "\(preset.id) must not include strength or cycling")
        }
    }

    @MainActor
    func testMainSectionRoundTripsAndKeepsIntervalsWhenInsertedTwice() throws {
        let owner = UUID()
        let warmup = try XCTUnwrap(ATHLTHRunningExercisePreset.progressive
            .blocks(in: .warmup).first)
        let main = ATHLTHRunningExercisePreset.fourByFour.blocks(in: .main)
        let cooldown = try XCTUnwrap(ATHLTHRunningExercisePreset.cooldown
            .blocks(in: .cooldown).first)

        XCTAssertTrue(ATHLTHRunningMainSet.save(
            title: "4 × 4", from: [warmup] + main + [cooldown], userID: owner
        ))
        let stored = try XCTUnwrap(ATHLTHRunningMainSet.load(userID: owner).first)
        XCTAssertEqual(stored.title, "4 × 4")
        XCTAssertEqual(stored.blocks.count, 2)
        XCTAssertEqual(stored.blocks.map(\.groupRounds), [4, 4])
        XCTAssertEqual(stored.blocks.map(\.durationSeconds), [240, 180])

        let first = stored.inserting()
        let second = stored.inserting()
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first[0].groupID, first[1].groupID)
        XCTAssertNotEqual(first[0].groupID, second[0].groupID)
        XCTAssertNotEqual(first[0].editorDragID, second[0].editorDragID)
        XCTAssertTrue(first.allSatisfy { $0.resolvedPhase == .main })
    }

    @MainActor
    func testRejectsStrengthBlocksAndBlankNames() {
        let owner = UUID()
        let running = ATHLTHRunningExercisePreset.easy.blocks(in: .main)
        XCTAssertFalse(ATHLTHRunningMainSet.save(
            title: "  ", from: running, userID: owner
        ))
        XCTAssertFalse(ATHLTHRunningMainSet.save(
            title: "No run", from: [], userID: owner
        ))
    }
}
