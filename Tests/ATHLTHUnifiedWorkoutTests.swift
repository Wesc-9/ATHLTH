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

    func testCyclingIsPreservedAsCyclingCategoryNotStrength() {
        var cycling = WorkoutTemplateBlock(
            sequence: 1, kind: .note, title: "Cycling",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 1800,
            targetWeightKilograms: nil, loadNote: nil, notes: nil
        )
        cycling.activityTag = "cycling"
        var workout = makeWorkout(kind: .strength)
        ATHLTHUnifiedWorkout.apply(
            blocks: [cycling], title: "Cycling session", routeID: nil,
            estimatedMinutes: 30, to: &workout
        )
        XCTAssertEqual(workout.kind, .custom)
        XCTAssertEqual(workout.workoutCategory, "cycling")
        XCTAssertEqual(workout.resolvedWorkoutBlocks, [cycling])
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

    func testWalkingBlocksKeepActivityRouteAndExactSeconds() throws {
        let groupID = UUID()
        var walk = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Gåintervall",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 525,
            targetWeightKilograms: nil, loadNote: nil, notes: nil
        )
        walk.cardioActivity = .walking
        walk.isIndoor = false
        walk.groupID = groupID
        walk.groupKind = .intervals
        walk.groupRounds = 4

        var rest = WorkoutTemplateBlock(
            sequence: 2, kind: .rest, title: "Pause",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 45,
            targetWeightKilograms: nil, loadNote: nil, notes: nil
        )
        rest.groupID = groupID
        rest.groupKind = .intervals
        rest.groupRounds = 4

        let route = UUID()
        var workout = makeWorkout(kind: .walking)
        ATHLTHUnifiedWorkout.apply(
            blocks: [walk, rest], title: "Gåintervaller",
            routeID: route, estimatedMinutes: 38, to: &workout
        )
        XCTAssertEqual(workout.kind, .walking)
        XCTAssertEqual(workout.routeID, route)

        let restored = try JSONDecoder().decode(
            PlannedSession.self, from: JSONEncoder().encode(workout)
        )
        XCTAssertEqual(restored.workoutBlocks?.first?.cardioActivity, .walking)
        XCTAssertEqual(restored.workoutBlocks?.first?.durationSeconds, 525)
        let timeline = restored.resolvedWorkoutBlocks.expandedForExecution()
        XCTAssertEqual(timeline.filter { $0.kind == .run }.count, 4)
        XCTAssertEqual(timeline.filter { $0.kind == .rest }.count, 3)
        XCTAssertTrue(timeline.filter { $0.kind == .run }.allSatisfy {
            $0.cardioActivity == .walking && $0.durationSeconds == 525
        })
    }

    func testIndoorWalkDoesNotPersistGPSRoute() {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Walk indoors",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 120,
            targetWeightKilograms: nil, loadNote: nil, notes: nil
        )
        block.cardioActivity = .walking
        block.isIndoor = true
        var workout = makeWorkout(kind: .walking)
        ATHLTHUnifiedWorkout.apply(
            blocks: [block], title: "Indoor walk", routeID: UUID(),
            estimatedMinutes: 2, to: &workout
        )
        XCTAssertNil(workout.routeID)
        XCTAssertEqual(workout.kind, .walking)
    }

    func testRunAndWalkTogetherIsHybrid() {
        var run = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Run",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 240,
            targetWeightKilograms: nil, loadNote: nil, notes: nil
        )
        run.cardioActivity = .running
        var walk = run
        walk.cardioActivity = .walking
        var workout = makeWorkout(kind: .running)
        ATHLTHUnifiedWorkout.apply(
            blocks: [run, walk], title: "Mixed", routeID: nil,
            estimatedMinutes: 8, to: &workout
        )
        XCTAssertEqual(workout.kind, .custom)
        XCTAssertEqual(workout.workoutCategory, "hybrid")
    }


    func testMixedWarmupCyclingMainStrengthCooldownRunIsSingleHybrid() {
        var cycle = WorkoutTemplateBlock(
            sequence: 1, kind: .note, title: "Oppvarming på sykkel",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 600,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .warmup
        )
        cycle.activityTag = "cycling"
        cycle.targetEffortRPE = 3
        let squat = WorkoutTemplateBlock(
            sequence: 2, kind: .exercise, title: "Knebøy",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: 8, durationSeconds: nil,
            targetWeightKilograms: 40, loadNote: nil,
            notes: nil, phase: .main
        )
        var jog = WorkoutTemplateBlock(
            sequence: 3, kind: .run, title: "Nedjogg",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 300,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .cooldown
        )
        jog.cardioActivity = .running
        let workoutBlocks = [cycle, squat, jog]
        let blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Styrke og kondisjon", kind: .custom,
            durationMinutes: 30, routeID: nil, blocks: workoutBlocks
        )
        XCTAssertTrue(blueprint.isValid)
        XCTAssertEqual(blueprint.category, "hybrid")
        let workout = blueprint.applying(to: nil)
        XCTAssertEqual(workout.workoutCategory, "hybrid")
        XCTAssertEqual(workout.resolvedWorkoutBlocks, workoutBlocks)
        XCTAssertEqual(workout.resolvedWorkoutBlocks.map(\.resolvedPhase),
                       [.warmup, .main, .cooldown])
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
