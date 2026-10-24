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

    func testExistingRunOnlyWorkoutKeepsItsOriginalOrderedSteps() {
        let workout = fourByFour()
        let steps = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
        XCTAssertEqual(steps.first?.resolvedPhase, .warmup)
        XCTAssertEqual(steps.last?.resolvedPhase, .cooldown)
        XCTAssertEqual(steps.filter { $0.kind == .exercise }.count, 0)
    }
}
