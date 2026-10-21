import Foundation
import XCTest
@testable import ATHLTH

final class TrainingPlanLibraryBrowseTests: XCTestCase {
    @MainActor
    func testStrengthFocusPlanIsIdentifiedAsStrengthNotGenericMuscleCategory() throws {
        let entry = try XCTUnwrap(ATHLTHCuratedTrainingPlans.entries.first {
            $0.slug == "focus-back-biceps"
        })
        XCTAssertEqual(entry.category, "muscle_focus")
        XCTAssertEqual(entry.trainingTypeIcon, "dumbbell.fill")
        XCTAssertEqual(entry.workoutKinds.count, entry.sessionsPerWeek)
        XCTAssertTrue(entry.workoutKinds.allSatisfy { $0 == .strength })
        XCTAssertFalse(entry.sessionOutline.isEmpty)
    }

    @MainActor
    func testAllCatalogPlansExposeCorrectWeeklyFrequency() {
        let plans = TrainingPlanCatalogEntry.bundledCatalog
        XCTAssertGreaterThanOrEqual(Set(plans.map(\.sessionsPerWeek)).count, 2)
        for plan in plans {
            XCTAssertEqual(plan.sessionBlueprints.count, plan.sessionsPerWeek)
        }
        let lowToHigh = plans.sorted { $0.sessionsPerWeek < $1.sessionsPerWeek }
        let highToLow = plans.sorted { $0.sessionsPerWeek > $1.sessionsPerWeek }
        XCTAssertLessThanOrEqual(lowToHigh.first!.sessionsPerWeek, lowToHigh.last!.sessionsPerWeek)
        XCTAssertGreaterThanOrEqual(highToLow.first!.sessionsPerWeek, highToLow.last!.sessionsPerWeek)
    }

    @MainActor
    func testPlanDetailsUseActualScheduledWorkoutBlocksWithSetsAndRepetitions() throws {
        let plan = try XCTUnwrap(ATHLTHCuratedTrainingPlans.entries.first {
            $0.slug == "focus-back-biceps"
        })
        let first = try XCTUnwrap(plan.sessionBlueprints.first)
        let workout = ATHLTHCatalogPlanSessionFactory.session(
            entry: plan, blueprint: first, week: 1
        )
        let exercises = workout.workoutBlocks.filter { $0.kind == .exercise }
        XCTAssertFalse(exercises.isEmpty)
        XCTAssertTrue(exercises.contains {
            ($0.setCount ?? 0) > 0 && ($0.repetitions ?? 0) > 0
        })
        XCTAssertTrue(exercises.contains { $0.targetText != nil })
    }

    @MainActor
    func testPreviewReflectsDifferentTargetsAcrossWeeks() throws {
        let plan = try XCTUnwrap(ATHLTHCuratedTrainingPlans.entries.first {
            $0.slug == "focus-back-biceps"
        })
        let blueprint = try XCTUnwrap(plan.sessionBlueprints.first)
        let regular = ATHLTHCatalogPlanSessionFactory.session(
            entry: plan, blueprint: blueprint, week: 3
        )
        let recovery = ATHLTHCatalogPlanSessionFactory.session(
            entry: plan, blueprint: blueprint, week: 4
        )
        let regularSets = regular.workoutBlocks.compactMap(\.setCount).reduce(0, +)
        let recoverySets = recovery.workoutBlocks.compactMap(\.setCount).reduce(0, +)
        XCTAssertGreaterThan(regularSets, recoverySets)
    }
}
