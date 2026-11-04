import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHAdvancedInlinePlanGroupTests: XCTestCase {
    func testIntervalQuickChoiceBuildsRealOrderedDragPauseBlocks() throws {
        let blocks = ATHLTHPlanInlineGroupFactory.intervals(
            rounds: 4, workSeconds: 30, recoverySeconds: 30,
            includeFinalRecovery: false
        )
        XCTAssertEqual(blocks.count, 7)
        XCTAssertEqual(blocks.filter { $0.kind == .run }.count, 4)
        XCTAssertEqual(blocks.filter { $0.kind == .rest }.count, 3)
        XCTAssertEqual(blocks.map(\.durationSeconds),
                       [30, 30, 30, 30, 30, 30, 30])
        XCTAssertTrue(blocks.allSatisfy {
            $0.groupID == blocks.first?.groupID &&
            $0.groupKind == .intervals && $0.groupRounds == 1 &&
            $0.phase == .main
        })
        XCTAssertNotNil(blocks.first?.groupID)
        XCTAssertEqual(blocks.expandedForExecution().count, 7)
        let summary = try XCTUnwrap(ATHLTHIntervalRecipeEditing.summary(
            for: try XCTUnwrap(blocks.first?.groupID), in: blocks
        ))
        XCTAssertEqual(summary.rounds, 4)
        XCTAssertEqual(summary.recoveryCount, 3)
        XCTAssertFalse(summary.hasFinalRecovery)
    }

    func testFinalRecoveryIsExplicitAndNotInvented() {
        let blocks = ATHLTHPlanInlineGroupFactory.intervals(
            rounds: 4, workSeconds: 45, recoverySeconds: 15,
            includeFinalRecovery: true
        )
        XCTAssertEqual(blocks.count, 8)
        XCTAssertEqual(blocks.last?.kind, .rest)
        XCTAssertEqual(blocks.last?.durationSeconds, 15)
        XCTAssertEqual(blocks.expandedForExecution().count, 8)
        XCTAssertEqual(ATHLTHWorkoutDurationEstimator.previewSeconds(
            for: blocks
        ), 240)
    }

    func testSupersetNeedsRealExercisesAndPreservesTheirIdentity() throws {
        var first = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Bench Press",
            exerciseSlug: "bench-press", distanceMeters: nil,
            repetitions: 10, durationSeconds: nil,
            targetWeightKilograms: 40, loadNote: nil,
            notes: nil, phase: .main, setCount: 4
        )
        first.exerciseID = UUID()
        var second = WorkoutTemplateBlock(
            sequence: 2, kind: .exercise, title: "Rows",
            exerciseSlug: "rows", distanceMeters: nil,
            repetitions: 12, durationSeconds: nil,
            targetWeightKilograms: 35, loadNote: nil,
            notes: nil, phase: .main, setCount: 3
        )
        second.exerciseID = UUID()
        let blocks = ATHLTHPlanInlineGroupFactory.superset(
            first: first, second: second, rounds: 3, restSeconds: 75
        )
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].exerciseID, first.exerciseID)
        XCTAssertEqual(blocks[1].exerciseID, second.exerciseID)
        XCTAssertEqual(blocks[0].repetitions, 10)
        XCTAssertEqual(blocks[1].repetitions, 12)
        XCTAssertNil(blocks[0].setCount)
        XCTAssertTrue(blocks.allSatisfy {
            $0.groupID == blocks.first?.groupID &&
            $0.groupKind == .superset && $0.groupRounds == 3
        })
        XCTAssertEqual(blocks.expandedForExecution().count, 8)
        XCTAssertTrue(ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Supersett", kind: .strength, durationMinutes: 30,
            routeID: nil, blocks: blocks
        ).isValid)

        let encoded = try JSONEncoder().encode(blocks)
        let restored = try JSONDecoder().decode(
            [WorkoutTemplateBlock].self, from: encoded
        )
        XCTAssertEqual(restored.map(\.exerciseID),
                       [first.exerciseID, second.exerciseID, nil])
        XCTAssertEqual(restored.expandedForExecution().count, 8)
    }

    func testIncompleteSupersetsCannotBeCommittedToATrainingPlan() {
        let first = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Only one exercise",
            exerciseSlug: "one", distanceMeters: nil, repetitions: 8,
            durationSeconds: nil, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .main
        )
        let note = WorkoutTemplateBlock(
            sequence: 2, kind: .note, title: "Not an exercise",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: nil, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .main
        )
        XCTAssertTrue(ATHLTHPlanInlineGroupFactory.superset(
            first: first, second: note, rounds: 3, restSeconds: 60
        ).isEmpty)
    }

    func testGroupIsStoredOnOnlyTheChosenDate() throws {
        let date = try XCTUnwrap(Calendar.current.date(
            from: DateComponents(year: 2026, month: 11, day: 2)
        ))
        let blocks = ATHLTHPlanInlineGroupFactory.intervals(
            rounds: 4, workSeconds: 60, recoverySeconds: 30,
            includeFinalRecovery: false
        )
        let blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Intervalløkt", kind: .running, durationMinutes: 10,
            routeID: nil, blocks: blocks
        )
        let saved = ATHLTHPlanWeekDayEdit(
            kind: .running, title: blueprint.title,
            durationMinutes: blueprint.durationMinutes, detailedWorkout: blueprint
        )
        var weeks = (1...2).map { w in
            TrainingPlanWeek(
                id: UUID(), weekNumber: w, title: "Week \(w)",
                days: (1...7).map { d in
                    TrainingPlanDay(id: UUID(), dayIndex: d,
                                    title: "Day \(d)", sessions: [])
                }
            )
        }
        // Wednesday of week 1 is key 3; week 2 must remain untouched.
        ATHLTHPlanWeekDayEdit.apply([3: saved], to: &weeks, startDate: date)
        XCTAssertEqual(weeks[0].days[2].sessions.count, 1)
        XCTAssertEqual(weeks[0].days[2].sessions.first?.workoutBlocks?.count, 7)
        XCTAssertTrue(weeks[1].days[2].sessions.isEmpty)
        let restored = try JSONDecoder().decode(
            ATHLTHPlanWeekDayEdit.self, from: JSONEncoder().encode(saved)
        )
        XCTAssertEqual(restored.detailedWorkout?.blocks.count, 7)
        XCTAssertEqual(restored.detailedWorkout?.title, "Intervalløkt")
    }

    func testActivityChipsDistinguishRunningTreadmillAndStrength() throws {
        let runner = try XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first {
                $0.type == .intervals
            }
        ).plannedSession()
        let chest = try XCTUnwrap(
            ATHLTHCuratedStrengthWorkouts.entries.first {
                $0.tags.contains("chest")
            }
        ).plannedSession()
        XCTAssertTrue(ATHLTHPlanWorkoutActivityFilter.running.matches(runner))
        XCTAssertFalse(ATHLTHPlanWorkoutActivityFilter.strength.matches(runner))
        XCTAssertTrue(ATHLTHPlanWorkoutActivityFilter.strength.matches(chest))
        XCTAssertFalse(ATHLTHPlanWorkoutActivityFilter.running.matches(chest))
        XCTAssertTrue(ATHLTHPlanWorkoutActivityFilter.all.matches(chest))
        XCTAssertTrue(ATHLTHPlanWorkoutActivityFilter.all.matches(runner))

        let treadmill = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Treadmill", kind: .running, durationMinutes: 20,
            routeID: nil,
            blocks: ATHLTHRunningExercisePreset.treadmill.blocks(in: .main)
        ).applying(to: nil)
        XCTAssertTrue(ATHLTHPlanWorkoutActivityFilter.running.matches(treadmill))
        XCTAssertFalse(ATHLTHPlanWorkoutActivityFilter.walking.matches(treadmill))
    }

    func testRunningSubfilterKeepsIntervalsWithoutShowingEasyRuns() throws {
        let interval = try XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first {
                $0.type == .intervals
            }
        )
        let easy = try XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first {
                $0.type == .easy
            }
        )
        let filter = ATHLTHWorkoutDiscoveryFilter(runningType: .intervals)
        XCTAssertTrue(filter.matches(interval))
        XCTAssertFalse(filter.matches(easy))
    }
}
