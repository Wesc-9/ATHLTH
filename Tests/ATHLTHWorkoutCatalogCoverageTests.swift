import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutCatalogCoverageTests: XCTestCase {
    @MainActor
    func testOfflineCatalogIncludesHybridAndStrengthPrescriptions() {
        let entries = WorkoutTemplateCatalogEntry.bundledCatalog
        XCTAssertEqual(entries.filter { $0.category == "hybrid" }.count, 3)
        let strengthEntries = entries.filter { $0.category == "strength" }
        let expectedStrengthEntries = ATHLTHCuratedStrengthWorkouts.entries
            + ATHLTHPremiumStrengthSessions.entries
            + ATHLTHGymCoachStrengthLibrary.workoutCatalogEntries
        XCTAssertEqual(strengthEntries.count, expectedStrengthEntries.count)
        XCTAssertEqual(Set(strengthEntries.map(\.id)), Set(expectedStrengthEntries.map(\.id)))
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        XCTAssertEqual(Set(entries.map(\.slug)).count, entries.count)
    }

    @MainActor
    func testEveryStrengthRecipeHasRealSetsRepsRestAndWarmup() {
        for entry in ATHLTHCuratedStrengthWorkouts.entries {
            XCTAssertEqual(entry.workoutKind, .strength)
            XCTAssertNotNil(entry.estimatedDurationMinutes)
            XCTAssertTrue(entry.blocks.contains { $0.resolvedPhase == .warmup })
            let exerciseBlocks = entry.blocks.filter { $0.kind == .exercise }
            XCTAssertGreaterThanOrEqual(exerciseBlocks.count, 4, entry.slug)
            XCTAssertTrue(exerciseBlocks.allSatisfy {
                ($0.setCount ?? 0) > 0 &&
                (($0.repetitions ?? 0) > 0 || ($0.durationSeconds ?? 0) > 0) &&
                ($0.restBetweenSetsSeconds ?? 0) > 0
            }, entry.slug)
            let session = entry.plannedSession()
            XCTAssertEqual(session.workoutCategory, "strength")
            XCTAssertEqual(session.resolvedWorkoutBlocks, entry.blocks)
            XCTAssertFalse(entry.blocks.expandedForExecution().isEmpty)
        }
    }

    @MainActor
    func testBuiltInRunningWorkoutRemainsNativeWhenUsedInTrainingPlan() {
        guard let run = RunningWorkoutLibraryStore.builtInTemplates.first else {
            return XCTFail("Built-in running workouts are missing")
        }
        let workout = run.plannedSession()
        XCTAssertEqual(workout.kind, .running)
        XCTAssertEqual(workout.runningWorkout?.id, run.id)
        XCTAssertEqual(workout.runningWorkout?.blocks, run.blocks)
        XCTAssertEqual(workout.routeID, run.routeID)
        XCTAssertFalse(run.recipePreviewBlocks.isEmpty)
        XCTAssertFalse(ATHLTHUnifiedWorkout.editorBlocks(from: workout).isEmpty)
    }

    @MainActor
    func testStrengthIdsRemainStableAcrossCatalogAccess() {
        let first = ATHLTHCuratedStrengthWorkouts.entries.map(\.id)
        let second = ATHLTHCuratedStrengthWorkouts.entries.map(\.id)
        XCTAssertEqual(first, second)
    }
}
