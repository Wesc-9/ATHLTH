import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHCompoundExerciseCatalogTests: XCTestCase {
    func testEveryBuiltInRunningMainIsIndexedWithoutWarmupOrCooldown() {
        let templates = RunningWorkoutLibraryStore.builtInTemplates
        let indexed = ATHLTHCompoundExerciseCatalog.build(
            running: templates, workoutCatalog: [], saved: []
        )
        XCTAssertGreaterThan(indexed.count, 25)
        for source in templates {
            let original = ATHLTHUnifiedWorkout.editorBlocks(
                from: source.plannedSession()
            )
            let main = ATHLTHCompoundExerciseCatalog.mainBlocks(original)
            guard !main.isEmpty else { continue }
            let matches = indexed.filter { $0.sourceIDs.contains(source.id) }
            XCTAssertEqual(matches.count, 1, "Main missing for \(source.title)")
            guard let match = matches.first else { continue }
            XCTAssertFalse(match.blocks.isEmpty)
            XCTAssertFalse(match.blocks.contains {
                $0.resolvedPhase == .warmup || $0.resolvedPhase == .cooldown
            })
        }
    }

    func testAllBundledWorkoutMainsAreInSameDirectory() {
        let templates = WorkoutTemplateCatalogEntry.bundledCatalog
        let indexed = ATHLTHCompoundExerciseCatalog.build(
            running: [], workoutCatalog: templates, saved: []
        )
        for template in templates {
            let main = ATHLTHCompoundExerciseCatalog.mainBlocks(template.blocks)
            guard main.contains(where: {
                $0.kind == .exercise || $0.kind == .run ||
                ($0.kind == .note && $0.durationSeconds != nil)
            }) else { continue }
            XCTAssertEqual(indexed.filter {
                $0.sourceIDs.contains(template.id)
            }.count, 1, "Unlinked bundled main: \(template.title)")
        }
    }

    func testFourByFourRecoveryVariantsShareFamilyButNotProtocol() throws {
        let entries = ATHLTHCompoundExerciseCatalog.build(
            running: RunningWorkoutLibraryStore.builtInTemplates,
            workoutCatalog: [], saved: []
        )
        let source = try XCTUnwrap(RunningWorkoutLibraryStore.builtInTemplates.first {
            $0.title == "4 × 4 intervaller"
        })
        let twoMinute = try XCTUnwrap(entries.first {
            $0.sourceIDs.contains(source.id)
        })
        XCTAssertEqual(twoMinute.category, .intervals)
        XCTAssertEqual(ATHLTHCompoundExerciseCatalog.fourByFourRecovery(
            twoMinute.blocks
        ), 120)
        let threeMinute = try XCTUnwrap(entries.first {
            ATHLTHCompoundExerciseCatalog.fourByFourRecovery($0.blocks) == 180
        })
        XCTAssertEqual(twoMinute.familyID, threeMinute.familyID)
        XCTAssertNotEqual(twoMinute.protocolID, threeMinute.protocolID)
    }

    func testPrivateSavedMainIsNotPublishedAndReuseDoesNotMutateOriginal() throws {
        let source = try XCTUnwrap(RunningWorkoutLibraryStore.builtInTemplates.first)
        let base = ATHLTHCompoundExerciseCatalog.mainBlocks(
            ATHLTHUnifiedWorkout.editorBlocks(from: source.plannedSession())
        )
        let privateMain = ATHLTHWorkoutMainSection(
            id: UUID(), sourceWorkoutID: UUID(),
            title: "Min intervall", kind: .running,
            blocks: base, savedAt: Date()
        )
        let entries = ATHLTHCompoundExerciseCatalog.build(
            running: [source], workoutCatalog: [], saved: [privateMain]
        )
        let personal = try XCTUnwrap(entries.first {
            $0.sourceIDs.contains(privateMain.id)
        })
        XCTAssertTrue(personal.isPersonal)
        XCTAssertEqual(personal.blocks, base)
        let first = personal.blocksForReuse()
        let second = personal.blocksForReuse()
        XCTAssertEqual(first.count, base.count)
        XCTAssertEqual(first.map(\.sequence), Array(1...base.count))
        XCTAssertEqual(personal.blocks, base)
        XCTAssertNotEqual(first.first?.editorDragID, second.first?.editorDragID)
    }

    func testDuplicatePublishedMainsShareOneIdentityAndKeepBothSources() throws {
        let source = try XCTUnwrap(RunningWorkoutLibraryStore.builtInTemplates.first)
        let originalMain = ATHLTHCompoundExerciseCatalog.mainBlocks(
            ATHLTHUnifiedWorkout.editorBlocks(from: source.plannedSession())
        )
        let publicCopy = WorkoutTemplateCatalogEntry(
            id: UUID(), slug: "copy-of-main",
            title: "Same protocol with another title", summary: "",
            category: "running", difficulty: "All levels",
            estimatedDurationMinutes: nil, tags: [],
            sourceLabel: nil, sourceURL: nil,
            blocks: originalMain, sortOrder: 0
        )
        let entries = ATHLTHCompoundExerciseCatalog.build(
            running: [source], workoutCatalog: [publicCopy], saved: []
        )
        let merged = try XCTUnwrap(entries.first {
            $0.sourceIDs.contains(source.id)
        })
        XCTAssertTrue(merged.sourceIDs.contains(publicCopy.id))
        XCTAssertEqual(entries.filter { $0.id == merged.id }.count, 1)
    }
}
