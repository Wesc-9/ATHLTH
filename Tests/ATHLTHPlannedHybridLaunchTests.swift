import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlannedHybridLaunchTests: XCTestCase {
    private func strengthExercise(
        _ title: String,
        phase: WorkoutPhaseKind
    ) -> PlannedExercise {
        var item = PlannedExercise(
            id: UUID(),
            exerciseID: nil,
            embeddedExercise: ExerciseSnapshot(
                name: title,
                instructions: [],
                primaryMuscles: [],
                equipment: [],
                imageURL: nil
            ),
            sets: 3,
            reps: 10,
            targetWeightKilograms: 20,
            targetRPE: nil,
            restSeconds: 60,
            notes: nil,
            targetRIR: nil,
            supersetGroupID: nil,
            progression: .none
        )
        item.workoutPhase = phase
        if phase == .warmup { item.setEntireExerciseWarmUp(true) }
        return item
    }

    @MainActor
    private func plannedHybrid() throws -> PlannedSession {
        let template = try XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first {
                $0.title == "4 × 4 intervaller"
            }
        )
        var session = PlannedSession(
            id: UUID(),
            title: "Hybrid 4 × 4",
            kind: .running,
            scheduledStart: nil,
            durationMinutes: 48,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [
                strengthExercise("Mobilisering", phase: .warmup),
                strengthExercise("Knebøy", phase: .main),
                strengthExercise("Uttøying", phase: .cooldown)
            ],
            notes: nil,
            runningWorkout: template
        )
        session.workoutCategory = "treadmill"
        return session
    }

    @MainActor
    func testPreparedFourByFourKeepsOneWorkoutAndAllNineTimedPhases() throws {
        let session = try plannedHybrid()
        let parts = try XCTUnwrap(
            ATHLTHHybridWorkoutLaunchPlan.parts(for: session)
        )
        XCTAssertEqual(parts.map(\.kind), [
            .strength, .running, .running, .strength, .running, .strength
        ])
        XCTAssertTrue(parts.allSatisfy { $0.id == session.id })
        let store = StrengthWorkoutStore()
        let watchID = UUID()
        XCTAssertTrue(store.startPlannedHybrid(
            session: session,
            validatedParts: parts,
            watchSessionID: watchID,
            trackingMode: .advanced,
            captureDevice: .appleWatch
        ))
        let active = try XCTUnwrap(store.activeWorkout)
        XCTAssertEqual(active.plannedSessionID, session.id)
        XCTAssertEqual(active.watchSessionID, watchID)
        XCTAssertEqual(active.captureDevice, .appleWatch)
        XCTAssertEqual(active.exercises.count, 6)

        let treadmillSegments = active.exercises.filter {
            $0.isEmbeddedRunningInterval == true
        }
        XCTAssertEqual(treadmillSegments.count, 3)
        XCTAssertEqual(
            treadmillSegments.flatMap(\.sets).count, 9
        )
        XCTAssertEqual(
            treadmillSegments.flatMap(\.sets)
                .compactMap(\.plannedDurationSeconds).reduce(0, +),
            42 * 60
        )
        XCTAssertEqual(
            active.exercises.filter {
                $0.isEmbeddedRunningInterval != true
            }.count,
            3
        )
        XCTAssertEqual(active.totalCompletedSets, 0)
    }

    @MainActor
    func testHybridRequiresExplicitTreadmillInsteadOfInventingGPS() throws {
        var session = try plannedHybrid()
        session.workoutCategory = "running"
        XCTAssertTrue(ATHLTHHybridWorkoutLaunchPlan.isCandidate(session))
        XCTAssertNil(ATHLTHHybridWorkoutLaunchPlan.parts(for: session))
        session.workoutCategory = "treadmill"
        session.targetDistanceKilometers = 5
        XCTAssertNotNil(ATHLTHHybridWorkoutLaunchPlan.parts(for: session))
        session.routeID = UUID()
        XCTAssertNil(ATHLTHHybridWorkoutLaunchPlan.parts(for: session))
    }

    @MainActor
    func testDistanceOnlyIntervalNeverCreatesPartialRecording() throws {
        var session = try plannedHybrid()
        session.runningWorkout = nil
        session.runningWorkouts = nil
        session.workoutBlocks = [
            WorkoutTemplateBlock(
                sequence: 1,
                kind: .run,
                title: "5 km",
                exerciseSlug: nil,
                distanceMeters: 5_000,
                repetitions: nil,
                durationSeconds: nil,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil,
                phase: .main,
                isIndoor: true
            ),
            WorkoutTemplateBlock(
                sequence: 2,
                kind: .exercise,
                title: "Knebøy",
                exerciseSlug: nil,
                distanceMeters: nil,
                repetitions: 10,
                durationSeconds: nil,
                targetWeightKilograms: 20,
                loadNote: nil,
                notes: nil,
                phase: .main
            )
        ]
        XCTAssertNil(ATHLTHHybridWorkoutLaunchPlan.parts(for: session))
    }
}
