import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHRunningWorkoutCopyPolicyTests: XCTestCase {
    private func source() throws -> RunningWorkoutTemplate {
        try XCTUnwrap(RunningWorkoutLibraryStore.builtInTemplates.first {
            $0.title == "4 × 4 intervaller"
        })
    }

    func testOriginalIsAlwaysInLibraryEvenWithPersonalVariant() throws {
        let original = try source()
        let store = RunningWorkoutLibraryStore()
        store.switchAccount(UUID())
        var variant = store.duplicate(original)
        XCTAssertTrue(store.customTemplates.isEmpty)
        XCTAssertNotEqual(variant.id, original.id)
        XCTAssertNotEqual(ATHLTHRunningWorkoutCopyPolicy.normalizedName(variant.title),
                          ATHLTHRunningWorkoutCopyPolicy.normalizedName(original.title))

        variant.blocks[0].title += " – min oppvarming"
        XCTAssertTrue(store.save(variant))
        XCTAssertTrue(store.allTemplates.contains(where: { $0.id == original.id && $0.isBuiltIn }))
        XCTAssertTrue(store.allTemplates.contains(where: { $0.id == variant.id && !$0.isBuiltIn }))
    }

    func testRenamingAloneCannotBeSaved() throws {
        let original = try source()
        let store = RunningWorkoutLibraryStore()
        store.switchAccount(UUID())
        let draft = store.duplicate(original)
        XCTAssertFalse(ATHLTHRunningWorkoutCopyPolicy.hasChanges(draft, comparedTo: original))
        XCTAssertNotNil(ATHLTHRunningWorkoutCopyPolicy.saveError(draft, comparedTo: original))
        XCTAssertFalse(store.save(draft))
        XCTAssertTrue(store.customTemplates.isEmpty)
    }

    func testChangedWorkoutCannotKeepOriginalName() throws {
        let original = try source()
        let store = RunningWorkoutLibraryStore()
        store.switchAccount(UUID())
        var draft = store.duplicate(original)
        draft.title = original.title
        draft.blocks[0].title += " – changed"
        XCTAssertTrue(ATHLTHRunningWorkoutCopyPolicy.hasChanges(draft, comparedTo: original))
        XCTAssertNotNil(ATHLTHRunningWorkoutCopyPolicy.saveError(draft, comparedTo: original))
        XCTAssertFalse(store.save(draft))
    }

    func testChangedAndRenamedWorkoutCanBeSaved() throws {
        let original = try source()
        let store = RunningWorkoutLibraryStore()
        store.switchAccount(UUID())
        var draft = store.duplicate(original)
        draft.blocks[0].title += " – personalized"
        XCTAssertNil(ATHLTHRunningWorkoutCopyPolicy.saveError(draft, comparedTo: original))
        XCTAssertTrue(store.save(draft))
        XCTAssertEqual(store.customTemplates.count, 1)
    }

    func testNewBlockIdentityAloneIsNotAMeaningfulWorkoutEdit() throws {
        let original = try source()
        let store = RunningWorkoutLibraryStore()
        var draft = store.duplicate(original)
        let old = draft.blocks[0]
        draft.blocks[0] = RunningWorkoutBlock(
            id: UUID(), kind: old.kind, title: old.title,
            repetitions: old.repetitions, work: old.work, recovery: old.recovery,
            notes: old.notes, repetitionOverrides: old.repetitionOverrides,
            spotifyPlaylist: old.spotifyPlaylist,
            intervalMotivation: old.intervalMotivation,
            recoveryStyle: old.recoveryStyle,
            spokenReport: old.spokenReport
        )
        XCTAssertFalse(ATHLTHRunningWorkoutCopyPolicy.hasChanges(draft, comparedTo: original))
    }
}
