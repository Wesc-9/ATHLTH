import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHWorkoutLibraryPersonalizationTests: XCTestCase {
    func testOnlyAdvancedFirstAddAsksToSetTargets() {
        XCTAssertFalse(ATHLTHWorkoutFirstUsePolicy.asksForTargets(
            advanced: false, hasPersonalCopy: false))
        XCTAssertFalse(ATHLTHWorkoutFirstUsePolicy.asksForTargets(
            advanced: false, hasPersonalCopy: true))
        XCTAssertTrue(ATHLTHWorkoutFirstUsePolicy.asksForTargets(
            advanced: true, hasPersonalCopy: false))
        XCTAssertFalse(ATHLTHWorkoutFirstUsePolicy.asksForTargets(
            advanced: true, hasPersonalCopy: true))
    }

    func testCatalogCopyStartsWithBlankTargetsAndPreservesStructure() {
        let original = WorkoutTemplateBlock(
            sequence: 1,
            kind: .run,
            title: "Intervall",
            exerciseSlug: nil,
            distanceMeters: nil,
            repetitions: nil,
            durationSeconds: 240,
            targetWeightKilograms: 50,
            loadNote: "Personal load",
            notes: "Four minutes of work",
            phase: .main,
            targetPaceSecondsPerKilometer: 285,
            targetHeartRateZone: 4
        )
        var withIncline = original
        withIncline.treadmillInclinePercent = 3
        withIncline.targetEffortRPE = 8
        let result = ATHLTHWorkoutLibraryPersonalization.blankTargets([withIncline])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].durationSeconds, 240)
        XCTAssertEqual(result[0].title, original.title)
        XCTAssertEqual(result[0].phase, .main)
        XCTAssertEqual(result[0].notes, original.notes)
        XCTAssertNil(result[0].targetPaceSecondsPerKilometer)
        XCTAssertNil(result[0].treadmillInclinePercent)
        XCTAssertNil(result[0].targetHeartRateZone)
        XCTAssertNil(result[0].targetWeightKilograms)
        XCTAssertNil(result[0].targetEffortRPE)
        XCTAssertNil(result[0].loadNote)
        XCTAssertEqual(withIncline.targetPaceSecondsPerKilometer, 285)
    }

    func testRunningStockTargetsAreClearedWithoutMutatingSource() throws {
        var original = try XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first {
                ATHLTHWorkoutSearch.normalized($0.title) == "4x4 intervaller"
            })
        original.blocks[0].work.intensity = RunningIntensityTarget(
            kind: .pace,
            paceMinSecondsPerKilometer: 330,
            paceMaxSecondsPerKilometer: 345,
            heartRateZone: nil,
            rpe: nil
        )
        original.blocks[0].work.treadmillInclinePercent = 4
        let result = ATHLTHRunningLibraryDefaults.unpersonalized(original)
        XCTAssertEqual(result.blocks.count, original.blocks.count)
        XCTAssertEqual(result.blocks[0].work.durationSeconds,
                       original.blocks[0].work.durationSeconds)
        XCTAssertNil(result.blocks[0].work.intensity.paceMinSecondsPerKilometer)
        XCTAssertNil(result.blocks[0].work.intensity.paceMaxSecondsPerKilometer)
        XCTAssertNil(result.blocks[0].work.treadmillInclinePercent)
        XCTAssertEqual(result.blocks[0].work.intensity.kind, .none)
        XCTAssertEqual(original.blocks[0].work.intensity.kind, .pace)
        XCTAssertEqual(original.blocks[0].work.treadmillInclinePercent, 4)
    }

    func testSavedPersonalRunningCopyUsesOriginalLibraryIdentity() throws {
        let source = try XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first {
                ATHLTHWorkoutSearch.normalized($0.title) == "4x4 intervaller"
            })
        let store = RunningWorkoutLibraryStore()
        let saved = store.duplicate(source)
        XCTAssertFalse(saved.isBuiltIn)
        XCTAssertEqual(saved.sharedSourceWorkoutID, source.id)
        XCTAssertEqual(store.savedCopy(for: source)?.id, saved.id)
        XCTAssertEqual(store.allTemplates.first(where: { $0.id == source.id })?.id,
                       source.id)
    }
}
