import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHUnifiedWorkoutTests: XCTestCase {
    func testStrengthSuggestionBecomesOneTimelineIncludingRecovery() {
        let movement = ExerciseSnapshot(
            name: "Squat",
            instructions: [],
            primaryMuscles: ["Quads"],
            equipment: ["Barbell"],
            imageURL: nil
        )
        var exercise = PlannedExercise(
            id: UUID(),
            exerciseID: nil,
            embeddedExercise: movement,
            sets: 2,
            reps: 10,
            targetWeightKilograms: 30,
            targetRPE: nil,
            restSeconds: 90,
            notes: nil
        )
        exercise.setTargets = [
            PlannedExerciseSetTarget(
                reps: 12, weightKilograms: 30, restSeconds: 75,
                isWarmUp: true
            ),
            PlannedExerciseSetTarget(
                reps: 8, weightKilograms: 40
            )
        ]
        var workout = makeWorkout(kind: .strength)
        workout.exercises = [exercise]

        let blocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)

        XCTAssertEqual(blocks.map(\.kind), [.exercise, .rest, .exercise])
        XCTAssertEqual(blocks[0].repetitions, 12)
        XCTAssertEqual(blocks[0].phase, .warmup)
        XCTAssertEqual(blocks[0].targetWeightKilograms, 30)
        XCTAssertEqual(blocks[1].durationSeconds, 75)
        XCTAssertEqual(blocks[2].repetitions, 8)
        XCTAssertEqual(blocks[2].targetWeightKilograms, 40)
    }

    func testSavingUnifiedBlocksEliminatesParallelExecutionCopies() {
        var workout = makeWorkout(kind: .strength)
        let identity = workout.id
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        workout.scheduledStart = date
        let block = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise,
            title: "Knebøy", exerciseSlug: nil,
            distanceMeters: nil, repetitions: 10,
            durationSeconds: nil, targetWeightKilograms: 30,
            loadNote: nil, notes: nil
        )
        ATHLTHUnifiedWorkout.apply(
            blocks: [block], title: " ", routeID: UUID(),
            estimatedMinutes: 15, to: &workout
        )
        XCTAssertEqual(workout.id, identity)
        XCTAssertEqual(workout.scheduledStart, date)
        XCTAssertEqual(workout.kind, .strength)
        XCTAssertEqual(workout.title, WorkoutKind.strength.title)
        XCTAssertNil(workout.routeID)
        XCTAssertTrue(workout.exercises.isEmpty)
        XCTAssertNil(workout.runningWorkout)
        XCTAssertTrue((workout.runningWorkouts ?? []).isEmpty)
        XCTAssertEqual(workout.resolvedWorkoutBlocks, [block])
        XCTAssertEqual(workout.durationMinutes, 15)
    }

    func testRunningIntervalRecoveryTurnsIntoExplicitTimelineSteps() {
        let running = RunningWorkoutBlock(
            kind: .work, title: "Intervall", repetitions: 3,
            work: .time(120), recovery: .time(60)
        )
        let template = RunningWorkoutTemplate(
            id: UUID(), title: "Intervaller", type: .intervals,
            summary: "", blocks: [running], routeID: nil,
            isBuiltIn: false, createdAt: Date(), updatedAt: Date()
        )
        var workout = makeWorkout(kind: .running)
        workout.runningWorkout = template

        let blocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)

        XCTAssertEqual(blocks.map(\.kind),
                       [.run, .rest, .run, .rest, .run])
        XCTAssertEqual(blocks.filter { $0.kind == .rest }.count, 2)
        XCTAssertEqual(
            ATHLTHWorkoutDurationEstimator.minutes(for: blocks), 10
        )
    }

    func testWalkingKeepsItsWorkoutClassification() {
        var workout = makeWorkout(kind: .walking)
        workout.durationMinutes = 30
        let blocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.kind, .run)

        ATHLTHUnifiedWorkout.apply(
            blocks: blocks, title: "", routeID: nil,
            estimatedMinutes: 30, to: &workout
        )
        XCTAssertEqual(workout.kind, .walking)
        XCTAssertEqual(workout.workoutCategory, "walking")
        XCTAssertTrue(workout.exercises.isEmpty)
    }

    private func makeWorkout(kind: WorkoutKind) -> PlannedSession {
        PlannedSession(
            id: UUID(), title: "", kind: kind,
            scheduledStart: nil, durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
    }
}
