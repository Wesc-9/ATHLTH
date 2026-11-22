import Foundation
import XCTest
@testable import ATHLTH

final class TrainingPlanLibraryBrowseTests: XCTestCase {
    @MainActor
    func testInvalidRemotePlanCannotHideBundledPlanAndDuplicateRemoteIsDeduplicated() throws {
        let bundled = try XCTUnwrap(ATHLTHCuratedTrainingPlans.entries.first)
        let invalid = TrainingPlanCatalogEntry(
            id: UUID(), slug: bundled.slug, title: "Invalid replacement",
            summary: "Bad remote plan", category: "running", goal: "Run",
            level: "Beginner", durationWeeks: 8, sessionsPerWeek: 3,
            workoutPattern: ["easy_run"], tags: [],
            sortOrder: 0, catalogVersion: 99
        )
        let valid = TrainingPlanCatalogEntry(
            id: UUID(), slug: "verified-one-day-remote", title: "Remote plan",
            summary: "", category: "running", goal: "Run",
            level: "Beginner", durationWeeks: 8, sessionsPerWeek: 1,
            workoutPattern: ["easy_run"], tags: [],
            sortOrder: 1, catalogVersion: 3
        )
        let olderDuplicate = TrainingPlanCatalogEntry(
            id: UUID(), slug: valid.slug, title: "Old remote revision",
            summary: "", category: "running", goal: "Run",
            level: "Beginner", durationWeeks: 8, sessionsPerWeek: 1,
            workoutPattern: ["easy_run"], tags: [],
            sortOrder: 2, catalogVersion: 1
        )
        let tooLong = TrainingPlanCatalogEntry(
            id: UUID(), slug: "invalid-53-week-remote", title: "Too long",
            summary: "", category: "running", goal: "Run",
            level: "Beginner", durationWeeks: 53, sessionsPerWeek: 1,
            workoutPattern: ["easy_run"], tags: [],
            sortOrder: 3, catalogVersion: 1
        )
        let stolenID = TrainingPlanCatalogEntry(
            id: bundled.id, slug: "rogue-remote-plan", title: "Wrong identity",
            summary: "", category: "running", goal: "Run",
            level: "Beginner", durationWeeks: 8, sessionsPerWeek: 1,
            workoutPattern: ["easy_run"], tags: [],
            sortOrder: 4, catalogVersion: 100
        )
        let alteredPrescription = TrainingPlanCatalogEntry(
            id: UUID(), slug: bundled.slug, title: "Changed recipe",
            summary: "", category: bundled.category,
            goal: bundled.goal, level: bundled.level,
            durationWeeks: bundled.durationWeeks,
            sessionsPerWeek: bundled.sessionsPerWeek,
            workoutPattern: Array(repeating: "easy_run",
                                  count: bundled.sessionsPerWeek),
            tags: [], sortOrder: 5, catalogVersion: 100
        )
        let replacementUUID = TrainingPlanCatalogEntry(
            id: UUID(), slug: bundled.slug, title: "Same recipe, new UUID",
            summary: "", category: bundled.category,
            goal: bundled.goal, level: bundled.level,
            durationWeeks: bundled.durationWeeks,
            sessionsPerWeek: bundled.sessionsPerWeek,
            workoutPattern: bundled.workoutPattern,
            tags: [], sortOrder: 6, catalogVersion: 101
        )
        let merged = TrainingPlanLibraryStore.mergeValidatedCatalog(
            remote: [olderDuplicate, invalid, tooLong, valid, stolenID,
                     alteredPrescription, replacementUUID]
        )
        XCTAssertEqual(merged.first { $0.slug == bundled.slug }?.id, bundled.id)
        XCTAssertEqual(merged.filter { $0.slug == valid.slug }.count, 1)
        XCTAssertEqual(merged.first { $0.slug == valid.slug }?.id, valid.id)
        XCTAssertFalse(merged.contains { $0.slug == tooLong.slug })
        XCTAssertFalse(merged.contains { $0.slug == stolenID.slug })
    }

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
    func testPlanPickerDefaultDaysMatchEverySupportedWeeklyFrequency() {
        for sessions in 1...7 {
            let days = TrainingPlanCatalogEntry.defaultDayIndexes(for: sessions)
            XCTAssertEqual(days.count, sessions)
            XCTAssertEqual(Set(days).count, sessions)
            XCTAssertTrue(days.allSatisfy { (1...7).contains($0) })
        }
        XCTAssertTrue(TrainingPlanCatalogEntry.defaultDayIndexes(for: 0).isEmpty)
        XCTAssertTrue(TrainingPlanCatalogEntry.defaultDayIndexes(for: 8).isEmpty)
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
        let exercises = (workout.workoutBlocks ?? []).filter { $0.kind == .exercise }
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
        let regularSets = (regular.workoutBlocks ?? []).compactMap(\.setCount).reduce(0, +)
        let recoverySets = (recovery.workoutBlocks ?? []).compactMap(\.setCount).reduce(0, +)
        XCTAssertGreaterThan(regularSets, recoverySets)
    }
}
