import Foundation
import XCTest
@testable import ATHLTH

/// Regression checks for real multi-week prescriptions, not merely list cards.
final class ATHLTHCuratedTrainingPlanTests: XCTestCase {
    @MainActor
    func testEveryBundledPlanHasStableIdentityAndRunnableBlueprints() {
        let entries = TrainingPlanCatalogEntry.bundledCatalog
        XCTAssertEqual(ATHLTHCuratedTrainingPlans.entries.count, 24)
        XCTAssertGreaterThanOrEqual(entries.count, 30)
        XCTAssertEqual(Set(entries.map(\.slug)).count, entries.count)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)

        for plan in entries {
            XCTAssertTrue((6...16).contains(plan.durationWeeks) ||
                          plan.slug == "marathon-build" || plan.tags.contains("zoned"), plan.slug)
            XCTAssertEqual(plan.workoutPattern.count, plan.sessionsPerWeek, plan.slug)
            XCTAssertEqual(plan.sessionBlueprints.count, plan.sessionsPerWeek, plan.slug)
            for blueprint in plan.sessionBlueprints {
                let workout = ATHLTHCatalogPlanSessionFactory.session(
                    entry: plan, blueprint: blueprint, week: 1
                )
                XCTAssertFalse(workout.resolvedWorkoutBlocks.isEmpty, plan.slug)
                XCTAssertNotNil(workout.durationMinutes, plan.slug)
                XCTAssertTrue(workout.isStructuredWorkout || blueprint == .mobility, plan.slug)
                XCTAssertTrue(workout.exercises.isEmpty, plan.slug)
                XCTAssertTrue(workout.resolvedRunningWorkouts.isEmpty, plan.slug)
            }
        }
    }

    @MainActor
    func testMuscleFocusedProgramsIncludeRealExerciseSetsRestAndWarmup() throws {
        let selected = ATHLTHCuratedTrainingPlans.entries.filter { $0.category == "muscle_focus" }
        XCTAssertGreaterThanOrEqual(selected.count, 7)
        for entry in selected {
            let types = entry.sessionBlueprints
            let workouts = types.map {
                ATHLTHCatalogPlanSessionFactory.session(entry: entry, blueprint: $0, week: 1)
            }
            XCTAssertTrue(workouts.allSatisfy { $0.kind == .strength }, entry.slug)
            XCTAssertTrue(workouts.allSatisfy { workout in
                workout.resolvedWorkoutBlocks.contains { $0.resolvedPhase == .warmup }
            }, entry.slug)
            XCTAssertTrue(workouts.allSatisfy { workout in
                workout.resolvedWorkoutBlocks.contains { block in
                    block.kind == .exercise && (block.setCount ?? 0) > 0 &&
                    ((block.repetitions ?? 0) > 0 || (block.durationSeconds ?? 0) > 0) &&
                    (block.restBetweenSetsSeconds ?? 0) > 0
                }
            }, entry.slug)
        }
        let chest = try XCTUnwrap(selected.first { $0.slug == "focus-chest-triceps" })
        let chestSessions = chest.sessionBlueprints
        XCTAssertEqual(chestSessions, [.chest, .legs, .push, .back])
    }

    @MainActor
    func testStrengthRecoveryWeekActuallyReducesSetVolume() throws {
        let plan = try XCTUnwrap(ATHLTHCuratedTrainingPlans.entries.first {
            $0.slug == "strength-upper-lower-foundation"
        })
        let blueprint = try XCTUnwrap(plan.sessionBlueprints.first)
        let regular = ATHLTHCatalogPlanSessionFactory.session(
            entry: plan, blueprint: blueprint, week: 3
        )
        let recovery = ATHLTHCatalogPlanSessionFactory.session(
            entry: plan, blueprint: blueprint, week: 4
        )
        func sets(_ workout: PlannedSession) -> Int {
            workout.resolvedWorkoutBlocks.compactMap(\.setCount).reduce(0, +)
        }
        XCTAssertGreaterThan(sets(regular), sets(recovery))
        XCTAssertTrue(recovery.notes?.contains("4/8") == true)
    }

    @MainActor
    func testWeeklyStrengthRepTargetsProgressGentlyWithoutInventingLoad() throws {
        let plan = try XCTUnwrap(ATHLTHCuratedTrainingPlans.entries.first {
            $0.slug == "focus-chest-triceps"
        })
        let first = ATHLTHCatalogPlanSessionFactory.session(
            entry: plan, blueprint: .chest, week: 1
        )
        let third = ATHLTHCatalogPlanSessionFactory.session(
            entry: plan, blueprint: .chest, week: 3
        )
        let secondary = ATHLTHCatalogPlanSessionFactory.session(
            entry: plan, blueprint: .push, week: 3
        )
        let standardPush = ATHLTHCatalogPlanSessionFactory.session(
            entry: try XCTUnwrap(ATHLTHCuratedTrainingPlans.entries.first {
                $0.slug == "strength-ppl-3"
            }), blueprint: .push, week: 3
        )
        let initialRep = try XCTUnwrap(first.resolvedWorkoutBlocks.first {
            $0.kind == .exercise
        }?.repetitions)
        let nextRep = try XCTUnwrap(third.resolvedWorkoutBlocks.first {
            $0.kind == .exercise
        }?.repetitions)
        XCTAssertEqual(nextRep, initialRep + 2)
        XCTAssertTrue(third.resolvedWorkoutBlocks.allSatisfy {
            $0.targetWeightKilograms == nil
        })
        let secondarySets = secondary.resolvedWorkoutBlocks.compactMap(\.setCount).reduce(0, +)
        let standardSets = standardPush.resolvedWorkoutBlocks.compactMap(\.setCount).reduce(0, +)
        XCTAssertLessThan(secondarySets, standardSets)
    }

    @MainActor
    func testCompetitivePlanReducesFatigueAtEndWithoutHardCodingPaceOrWeight() throws {
        let race = try XCTUnwrap(ATHLTHCuratedTrainingPlans.entries.first {
            $0.slug == "race-marathon"
        })
        let longRun: TrainingPlanCatalogSessionBlueprint = .longRun
        let middle = ATHLTHCatalogPlanSessionFactory.session(
            entry: race, blueprint: longRun, week: 12
        )
        let final = ATHLTHCatalogPlanSessionFactory.session(
            entry: race, blueprint: longRun, week: 16
        )
        XCTAssertEqual(middle.kind, .running)
        XCTAssertLessThan(final.durationMinutes ?? 0, middle.durationMinutes ?? 0)
        XCTAssertTrue(final.resolvedWorkoutBlocks.allSatisfy {
            $0.targetPaceSecondsPerKilometer == nil &&
            $0.targetWeightKilograms == nil
        })
        XCTAssertTrue(final.notes?.contains("16/16") == true)
    }

    @MainActor
    func testProgramPersistenceCreatesDistinctSessionsWithoutLostExercises() throws {
        let suite = "ATHLTHCuratedPlanTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        let entry = try XCTUnwrap(ATHLTHCuratedTrainingPlans.entries.first {
            $0.slug == "focus-glutes-hamstrings"
        })
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2032, month: 5, day: 10
        )))
        let plan = try XCTUnwrap(store.scheduleCatalogPlan(
            entry, startDate: date, preferredDayIndexes: [2, 4, 6]
        ))
        XCTAssertEqual(plan.weeks.count, entry.durationWeeks)
        XCTAssertEqual(plan.weeks.flatMap(\.days).flatMap(\.sessions).count,
                       entry.durationWeeks * entry.sessionsPerWeek)

        let workouts = plan.weeks.flatMap(\.days).flatMap(\.sessions)
        XCTAssertEqual(Set(workouts.map(\.id)).count, workouts.count)
        XCTAssertTrue(workouts.allSatisfy {
            $0.kind == .strength && !$0.resolvedWorkoutBlocks.isEmpty
        })
        let first = try XCTUnwrap(workouts.first)
        XCTAssertTrue(first.resolvedWorkoutBlocks.contains {
            $0.title.localizedCaseInsensitiveContains("hip thrust") ||
            $0.title.localizedCaseInsensitiveContains("Romanian")
        })
        // Saved catalog sessions retain the same execution recipe.
        let data = try JSONEncoder().encode(first)
        let roundTrip = try JSONDecoder().decode(PlannedSession.self, from: data)
        XCTAssertEqual(first.resolvedWorkoutBlocks, roundTrip.resolvedWorkoutBlocks)
    }

    @MainActor
    func testPlanMuscleFilterReusesExerciseLibraryGroupsWithoutFalseMatches() throws {
        let plans = TrainingPlanCatalogEntry.bundledCatalog
        let chest = try XCTUnwrap(plans.first { $0.slug == "focus-chest-triceps" })
        XCTAssertTrue(chest.explicitlyTargets(.chest))
        XCTAssertTrue(chest.explicitlyTargets(.triceps))
        XCTAssertFalse(chest.explicitlyTargets(.calves))

        let pull = try XCTUnwrap(plans.first { $0.slug == "focus-back-biceps" })
        XCTAssertTrue(pull.explicitlyTargets(.back))
        XCTAssertTrue(pull.explicitlyTargets(.biceps))
        XCTAssertFalse(pull.explicitlyTargets(.quads))

        let posterior = try XCTUnwrap(plans.first { $0.slug == "focus-glutes-hamstrings" })
        XCTAssertTrue(posterior.explicitlyTargets(.glutes))
        XCTAssertTrue(posterior.explicitlyTargets(.hamstrings))

        let first5K = try XCTUnwrap(plans.first { $0.slug == "first-5k" })
        XCTAssertFalse(ExerciseMuscleGroup.allCases.contains {
            first5K.explicitlyTargets($0)
        })
    }
}
