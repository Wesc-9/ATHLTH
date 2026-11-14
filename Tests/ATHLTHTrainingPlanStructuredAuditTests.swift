import Foundation
import XCTest
@testable import ATHLTH

/// Whole-catalog plan audit: source week -> executable workout blocks ->
/// calendar schedule. Text-only repetition hints are not accepted as a plan.
final class ATHLTHTrainingPlanStructuredAuditTests: XCTestCase {
    @MainActor
    func testEveryZonedPlanPreservesRequiredWeeksSessionsAndSourceTargets() throws {
        XCTAssertEqual(ATHLTHZonedPlanLibrary.plans.count, 10)
        var totalRequired = 0
        var scaledSessions = 0
        for plan in ATHLTHZonedPlanLibrary.plans {
            XCTAssertEqual(plan.weeks.count, plan.totalWeeks, plan.id)
            for (index, week) in plan.weeks.enumerated() {
                XCTAssertEqual(week.weekNumber, index + 1, plan.id)
                let required = ATHLTHZonedPlanLibrary.orderedRequiredSessions(in: week)
                XCTAssertEqual(required.count, plan.sessionsPerWeek,
                               "\(plan.id) / week \(week.weekNumber)")
                totalRequired += required.count
                for source in required {
                    let session = try XCTUnwrap(
                        ATHLTHZonedPlanLibrary.plannedSession(
                            source, week: week, sourcePlan: plan
                        ),
                        "\(plan.id) / week \(week.weekNumber) / \(source.workoutId)"
                    )
                    let blocks = session.resolvedWorkoutBlocks
                    XCTAssertFalse(blocks.isEmpty)
                    XCTAssertEqual(
                        blocks.map(\.sequence), Array(1...blocks.count),
                        "All plan steps must have usable ordered indices"
                    )
                    XCTAssertNil(session.targetPaceSecondsPerKilometer,
                                 "Source-example pace is not a personal target")
                    XCTAssertEqual(
                        session.targetDistanceKilometers,
                        source.workoutId == "__race_day__"
                            ? session.targetDistanceKilometers : source.targetDistanceKm
                    )
                    XCTAssertEqual(
                        blocks.expandedForExecution().count,
                        blocks.count,
                        "Plan steps should not gain or lose targets during expansion"
                    )
                    if let scaled = source.scaledRepetitions {
                        scaledSessions += 1
                        let authored = try XCTUnwrap(
                            ATHLTHZonedPlanLibrary.workouts.first {
                                $0.id == source.workoutId
                            }
                        )
                        let top = try XCTUnwrap(authored.mainSetStructure?.first)
                        let outerRepeats = top.count ?? 1
                        let nested = top.steps?.count == 1 &&
                            top.steps?.first?.kind == "repeat"
                        let expectedEfforts = nested
                            ? scaled * outerRepeats : scaled
                        let actualEfforts = blocks.filter {
                            $0.resolvedPhase == .main &&
                            $0.kind == .run
                        }.count
                        XCTAssertEqual(
                            actualEfforts, expectedEfforts,
                            "\(plan.id)/\(week.weekNumber)/\(source.workoutId)"
                        )
                        // The source's outer groups are retained; no pause
                        // is added after a final effort unless authored.
                        XCTAssertEqual(blocks.filter {
                            $0.resolvedPhase == .recovery
                        }.count, nested
                            ? outerRepeats * (scaled - 1) + outerRepeats - 1
                            : max(0, scaled - 1))
                    }
                }
            }
        }
        XCTAssertEqual(totalRequired, 446)
        XCTAssertEqual(scaledSessions, 28)
    }

    @MainActor
    func testAllCuratedAndFallbackPlansHaveUsableWeekBlueprints() {
        let catalog = ATHLTHCuratedTrainingPlans.entries +
            TrainingPlanCatalogEntry.fallbackCatalog
        XCTAssertEqual(ATHLTHCuratedTrainingPlans.entries.count, 24)
        XCTAssertEqual(TrainingPlanCatalogEntry.fallbackCatalog.count, 6)
        for plan in catalog {
            XCTAssertTrue(plan.hasCompleteWorkoutPattern, plan.slug)
            XCTAssertEqual(plan.sessionBlueprints.count, plan.sessionsPerWeek,
                           "Unrecognized or dropped sessions in \(plan.slug)")
            XCTAssertGreaterThan(plan.durationWeeks, 0)
            for week in 1...plan.durationWeeks {
                for blueprint in plan.sessionBlueprints {
                    let session = ATHLTHCatalogPlanSessionFactory.session(
                        entry: plan, blueprint: blueprint, week: week
                    )
                    XCTAssertFalse(session.resolvedWorkoutBlocks.isEmpty,
                                   "\(plan.slug)/\(week)/\(blueprint.rawValue)")
                    XCTAssertTrue(session.resolvedWorkoutBlocks.allSatisfy {
                        ($0.durationSeconds ?? 0) >= 0 &&
                        ($0.distanceMeters ?? 0) >= 0
                    })
                    let encoded = try? JSONEncoder().encode(session)
                    XCTAssertNotNil(encoded)
                    let restored = encoded.flatMap {
                        try? JSONDecoder().decode(PlannedSession.self, from: $0)
                    }
                    XCTAssertEqual(
                        restored?.resolvedWorkoutBlocks,
                        session.resolvedWorkoutBlocks,
                        "Typed fields lost in plan serialization"
                    )
                }
            }
        }
    }

    @MainActor
    func testAllGymCoachPlansKeepSourceStrengthGoalsAcrossWeekRotations() {
        XCTAssertEqual(ATHLTHGymCoachStrengthLibrary.programs.count, 11)
        for program in ATHLTHGymCoachStrengthLibrary.programs {
            let expectedDays = ATHLTHGymCoachStrengthLibrary.sessionsPerWeek(program)
            for week in 1...8 {
                let sources = ATHLTHGymCoachStrengthLibrary.sourceWorkouts(
                    for: program, week: week
                )
                XCTAssertEqual(sources.count, expectedDays, program.slug)
                for source in sources {
                    let result = ATHLTHGymCoachStrengthLibrary.plannedSession(
                        source, program: program, week: week
                    )
                    let goalBlocks = result.resolvedWorkoutBlocks.filter {
                        $0.kind == .exercise
                    }
                    XCTAssertEqual(goalBlocks.count, source.exercises.count,
                                   "\(program.slug)/\(source.name)")
                    for (exercise, block) in zip(source.exercises, goalBlocks) {
                        XCTAssertEqual(block.setCount, exercise.targetSets)
                        XCTAssertEqual(block.repetitions, exercise.targetRepsMin)
                        XCTAssertEqual(block.targetRepetitionsMaximum,
                                       exercise.targetRepsMax)
                        XCTAssertEqual(block.targetRepsInReserve, exercise.targetRIR)
                        XCTAssertEqual(block.targetMovementTempo, exercise.tempo)
                        XCTAssertEqual(block.sourceSupersetGroupIndex,
                                       exercise.supersetGroup)
                    }
                }
            }
        }
    }

    @MainActor
    func testCatalogPlanFactoryCarriesCompleteStructuredStrengthTargets() throws {
        let entry = try XCTUnwrap(ATHLTHCuratedTrainingPlans.entries.first {
            $0.slug == "strength-two-day-consistency"
        })
        let workout = ATHLTHCatalogPlanSessionFactory.session(
            entry: entry, blueprint: .fullBodyA, week: 2
        )
        let original = try XCTUnwrap(
            ATHLTHCuratedStrengthWorkouts.entries.first
        )
        let generated = workout.resolvedWorkoutBlocks
        XCTAssertEqual(generated.count, original.blocks.count)
        for (source, target) in zip(original.blocks, generated) {
            XCTAssertEqual(target.exerciseSlug, source.exerciseSlug)
            XCTAssertEqual(target.restBetweenSetsSeconds,
                           source.restBetweenSetsSeconds)
            XCTAssertEqual(target.sourceIntensityZoneLabel,
                           source.sourceIntensityZoneLabel)
            XCTAssertEqual(target.targetHeartRatePercentMin,
                           source.targetHeartRatePercentMin)
            XCTAssertEqual(target.targetHeartRatePercentMax,
                           source.targetHeartRatePercentMax)
            XCTAssertEqual(target.targetRepsInReserve,
                           source.targetRepsInReserve)
            XCTAssertEqual(target.targetMovementTempo,
                           source.targetMovementTempo)
            XCTAssertEqual(target.targetTerrainType,
                           source.targetTerrainType)
            XCTAssertEqual(target.activityTag, source.activityTag)
            XCTAssertEqual(target.exerciseSnapshot, source.exerciseSnapshot)
        }
    }

    @MainActor
    func testInvalidCatalogBlueprintIsNotSilentlyReplacedByUnrelatedWorkouts() {
        let bad = TrainingPlanCatalogEntry(
            id: UUID(), slug: "unsupported-source-template",
            title: "Unsupported", summary: "", category: "running",
            goal: "", level: "", durationWeeks: 8, sessionsPerWeek: 3,
            workoutPattern: ["easy_run", "unrecognized_workout", "long_run"],
            tags: [], sortOrder: 1, catalogVersion: 1
        )
        XCTAssertFalse(bad.hasCompleteWorkoutPattern)
        let suite = "ATHLTHInvalidPlanAudit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        XCTAssertNil(store.saveCatalogPlanTemplate(bad))
        XCTAssertNil(store.scheduleCatalogPlan(
            bad, startDate: start, preferredDayIndexes: [1, 3, 5]
        ))
        XCTAssertTrue(store.trainingPlans.isEmpty)
    }

    @MainActor
    func testFullZonedPlanSchedulesEveryWeekWithoutDroppingSourceSessions() throws {
        let plan = try XCTUnwrap(ATHLTHZonedPlanLibrary.catalogEntries.first {
            $0.slug == "zoned-10k-intermediaire"
        })
        let source = try XCTUnwrap(ATHLTHZonedPlanLibrary.plan(for: plan.slug))
        let suite = "ATHLTHPlanAudit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSessionStore(defaults: defaults)
        let start = try XCTUnwrap(Calendar.current.date(from:
            DateComponents(year: 2030, month: 1, day: 7)))
        let result = try XCTUnwrap(store.scheduleCatalogPlan(
            plan, startDate: start, preferredDayIndexes: [1, 3, 5, 7]
        ))
        XCTAssertEqual(result.weeks.count, source.totalWeeks)
        for (index, week) in result.weeks.enumerated() {
            let authoredWeek = source.weeks[index]
            XCTAssertEqual(week.sourcePlanPhase, authoredWeek.phase)
            XCTAssertEqual(week.sourcePlanRecoveryWeek, authoredWeek.isRecoveryWeek)
            XCTAssertEqual(week.sourcePlanVolumePercent, authoredWeek.volumePercent)
            XCTAssertEqual(week.sourcePlanRunningKilometers, authoredWeek.targetKm)
            XCTAssertEqual(week.sourcePlanLongRunKilometers,
                           authoredWeek.targetLongRunKm)
            XCTAssertEqual(week.sourcePlanWeeklyLoadScore,
                           authoredWeek.weeklyLoadScore)

            let scheduled = week.days.flatMap(\.sessions)
            let required = ATHLTHZonedPlanLibrary.orderedRequiredSessions(
                in: authoredWeek
            )
            XCTAssertEqual(scheduled.count, required.count)
            for (session, sourceSession) in zip(scheduled, required) {
                XCTAssertFalse(session.resolvedWorkoutBlocks.isEmpty)
                XCTAssertTrue(session.resolvedWorkoutBlocks.allSatisfy {
                    $0.sequence > 0
                })
                XCTAssertEqual(session.sourcePlanLoadScore, sourceSession.loadScore)
                XCTAssertEqual(session.sourcePlanIsKeySession,
                               sourceSession.isKeySession)
                XCTAssertEqual(session.sourcePlanSessionType,
                               sourceSession.sessionType)
                XCTAssertEqual(session.sourcePlanScaledRepetitions,
                               sourceSession.scaledRepetitions)
                XCTAssertEqual(session.sourcePaceExamples?.count,
                               sourceSession.paceNotes?.count)
            }
        }
    }
}
