import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHUnifiedMixedWorkoutPlanTests: XCTestCase {
    private func plannedExercise(
        _ name: String,
        phase: WorkoutPhaseKind
    ) -> PlannedExercise {
        var planned = PlannedExercise(
            id: UUID(),
            exerciseID: nil,
            embeddedExercise: ExerciseSnapshot(
                name: name,
                instructions: [],
                primaryMuscles: [],
                equipment: [],
                imageURL: nil
            ),
            sets: 1,
            reps: 10,
            targetWeightKilograms: nil,
            targetRPE: nil,
            restSeconds: nil,
            notes: nil,
            targetRIR: nil,
            supersetGroupID: nil,
            progression: StrengthProgressionRule.none
        )
        planned.workoutPhase = phase
        if phase == .warmup {
            planned.setEntireExerciseWarmUp(true)
        }
        return planned
    }

    @MainActor
    private func fourByFour() -> PlannedSession {
        var workout = PlannedSession(
            id: UUID(),
            title: "4 × 4 intervaller",
            kind: .running,
            scheduledStart: nil,
            durationMinutes: 42,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
        workout.runningWorkout = RunningWorkoutLibraryStore.builtInTemplates
            .first { $0.title == "4 × 4 intervaller" }
        XCTAssertNotNil(workout.runningWorkout)
        return workout
    }

    @MainActor
    func testIntervalPrescriptionsSurvivePhaseAwareSupplementaryExercises() {
        var workout = fourByFour()
        workout.exercises = [
            plannedExercise("Dynamisk oppvarming", phase: .warmup),
            plannedExercise("Knebøy", phase: .main),
            plannedExercise("Uttøying", phase: .cooldown)
        ]

        let steps = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
        XCTAssertEqual(steps.map(\.sequence), Array(1...steps.count))
        XCTAssertEqual(workout.kind, .running)

        guard let warmup = steps.firstIndex(where: {
            $0.kind == .exercise && $0.title == "Dynamisk oppvarming"
        }), let firstRun = steps.firstIndex(where: {
            $0.kind == .run
        }), let main = steps.firstIndex(where: {
            $0.kind == .exercise && $0.title == "Knebøy"
        }), let cooldown = steps.firstIndex(where: {
            $0.kind == .exercise && $0.title == "Uttøying"
        }) else {
            return XCTFail("All programmed phases must be visible")
        }

        XCTAssertLessThan(warmup, firstRun)
        XCTAssertLessThan(firstRun, main)
        XCTAssertLessThan(main, cooldown)

        // The interval library owns the actual work/recovery repetitions.
        XCTAssertEqual(steps.filter {
            $0.kind == .run && $0.durationSeconds == 240
        }.count, 4)
        XCTAssertEqual(steps.filter {
            $0.resolvedPhase == .recovery &&
            $0.durationSeconds == 120
        }.count, 3)
        XCTAssertEqual(steps.filter { $0.kind == .exercise }.count, 3)
    }

    @MainActor
    func testExercisePlacementRoundTripsWithoutChangingRunRecipe() throws {
        var workout = fourByFour()
        workout.exercises = [
            plannedExercise("Uttøying", phase: .cooldown)
        ]
        let copy = try JSONDecoder().decode(
            PlannedSession.self, from: JSONEncoder().encode(workout)
        )
        XCTAssertEqual(copy.exercises[0].workoutPhase, .cooldown)
        XCTAssertEqual(
            copy.resolvedRunningWorkouts.first?.blocks,
            workout.resolvedRunningWorkouts.first?.blocks
        )
    }

    @MainActor
    func testExistingRunOnlyWorkoutKeepsItsOriginalOrderedSteps() {
        let workout = fourByFour()
        let steps = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
        XCTAssertEqual(steps.first?.resolvedPhase, .warmup)
        XCTAssertEqual(steps.last?.resolvedPhase, .cooldown)
        XCTAssertEqual(steps.filter { $0.kind == .exercise }.count, 0)
    }

    func testPlanStudioTreadmillInclineSurvivesGroupedIntervalsAndSaving() throws {
        let groupID = UUID()
        var work = WorkoutTemplateBlock(
            sequence: 1,
            kind: .run,
            title: "4-minute treadmill effort",
            exerciseSlug: nil,
            distanceMeters: nil,
            repetitions: nil,
            durationSeconds: 240,
            targetWeightKilograms: nil,
            loadNote: nil,
            notes: nil,
            phase: .main,
            targetPaceSecondsPerKilometer: 285,
            targetHeartRateZone: 4
        )
        work.isIndoor = true
        work.groupID = groupID
        work.groupKind = .intervals
        work.groupRounds = 4
        work.treadmillInclinePercent = 2.5

        var recovery = WorkoutTemplateBlock(
            sequence: 2,
            kind: .rest,
            title: "2-minute recovery",
            exerciseSlug: nil,
            distanceMeters: nil,
            repetitions: nil,
            durationSeconds: 120,
            targetWeightKilograms: nil,
            loadNote: nil,
            notes: nil,
            phase: .recovery
        )
        recovery.groupID = groupID
        recovery.groupKind = .intervals
        recovery.groupRounds = 4

        let saved = try JSONDecoder().decode(
            [WorkoutTemplateBlock].self,
            from: JSONEncoder().encode([work, recovery])
        )
        XCTAssertEqual(saved[0].treadmillInclinePercent, 2.5)
        XCTAssertTrue(saved[0].targetText?.contains("2.5 %") == true)

        let execution = saved.expandedForExecution()
        XCTAssertEqual(execution.filter { $0.kind == .run }.count, 4)
        XCTAssertEqual(execution.filter { $0.kind == .rest }.count, 3)
        XCTAssertTrue(execution.filter { $0.kind == .run }
            .allSatisfy { $0.treadmillInclinePercent == 2.5 })
        XCTAssertTrue(execution.filter { $0.kind == .rest }
            .allSatisfy { $0.treadmillInclinePercent == nil })
    }

    func testLegacyPlanBlocksDecodeWithoutInclineTarget() throws {
        let old = WorkoutTemplateBlock(
            sequence: 1,
            kind: .run,
            title: "Original outdoors",
            exerciseSlug: nil,
            distanceMeters: 5_000,
            repetitions: nil,
            durationSeconds: nil,
            targetWeightKilograms: nil,
            loadNote: nil,
            notes: nil
        )
        let recovered = try JSONDecoder().decode(
            WorkoutTemplateBlock.self,
            from: JSONEncoder().encode(old)
        )
        XCTAssertNil(recovered.treadmillInclinePercent)
        XCTAssertEqual(recovered.title, "Original outdoors")
    }
}
