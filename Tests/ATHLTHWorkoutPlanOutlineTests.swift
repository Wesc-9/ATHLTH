import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHWorkoutPlanOutlineTests: XCTestCase {
    func testFourByFourShowsRealWarmupWorkThreeRecoveriesAndCoolDown() {
        let run = RunningWorkoutTemplate(
            id: UUID(),
            title: "4 × 4",
            type: .intervals,
            summary: "Intervals",
            blocks: [
                RunningWorkoutBlock(
                    kind: .warmup,
                    title: "Oppvarming",
                    work: .time(600, intensity: .easy)
                ),
                RunningWorkoutBlock(
                    kind: .work,
                    title: "4 × 4",
                    repetitions: 4,
                    work: .time(240),
                    recovery: .time(120)
                ),
                RunningWorkoutBlock(
                    kind: .cooldown,
                    title: "Nedjogg",
                    work: .time(600, intensity: .easy)
                )
            ],
            routeID: nil,
            isBuiltIn: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        var planned = session(kind: .running)
        planned.runningWorkout = run
        planned.runningWorkouts = [run]

        let rows = ATHLTHWorkoutPlanOutline.items(for: planned)
        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(rows[0].detail.contains("10 min"))
        XCTAssertTrue(rows[1].detail.contains("4 × 4 min"))
        XCTAssertTrue(rows[2].detail.contains("3 × 2 min"))
        XCTAssertTrue(rows[3].detail.contains("10 min"))
    }

    func testStrengthOutlineUsesActualExerciseTargets() {
        let exercise = Exercise(
            id: UUID(),
            origin: .custom,
            ownerID: UUID(),
            name: "Benkpress",
            instructions: [],
            primaryMuscles: ["Chest"],
            secondaryMuscles: [],
            equipment: [],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: false
        )
        var planned = session(kind: .strength)
        planned.exercises = [
            PlannedExercise(
                id: UUID(),
                exerciseID: exercise.id,
                embeddedExercise: exercise.snapshot,
                sets: 3,
                reps: 8,
                targetWeightKilograms: 60,
                targetRPE: nil,
                restSeconds: 120,
                notes: nil
            )
        ]
        let rows = ATHLTHWorkoutPlanOutline.items(for: planned)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].title, "Benkpress")
        XCTAssertTrue(rows[0].detail.contains("3 × 8"))
        XCTAssertTrue(rows[0].detail.contains("60"))
    }

    func testOrderedStructuredBlocksTakePriorityOverLegacyRepresentations() {
        var planned = session(kind: .custom)
        planned.workoutBlocks = [
            WorkoutTemplateBlock(
                sequence: 2,
                kind: .rest,
                title: "Pause",
                exerciseSlug: nil,
                distanceMeters: nil,
                repetitions: nil,
                durationSeconds: 120,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil
            ),
            WorkoutTemplateBlock(
                sequence: 1,
                kind: .run,
                title: "Oppvarming",
                exerciseSlug: nil,
                distanceMeters: nil,
                repetitions: nil,
                durationSeconds: 600,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil
            )
        ]

        let rows = ATHLTHWorkoutPlanOutline.items(for: planned)
        XCTAssertEqual(rows.map(\.title), ["Oppvarming", "Pause"])
        XCTAssertTrue(rows[0].detail.contains("10 min"))
        XCTAssertTrue(rows[1].detail.contains("2 min"))
    }

    private func session(kind: WorkoutKind) -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: "Test",
            kind: kind,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
    }
}
