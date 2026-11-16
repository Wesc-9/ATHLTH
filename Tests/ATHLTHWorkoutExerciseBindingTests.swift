import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHWorkoutExerciseBindingTests: XCTestCase {
    private func workout(
        _ title: String = "Strength",
        blocks: [WorkoutTemplateBlock] = [],
        exercises: [PlannedExercise] = []
    ) -> PlannedSession {
        var workout = PlannedSession(
            id: UUID(), title: title, kind: .strength,
            scheduledStart: nil, durationMinutes: 40,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: exercises, notes: nil
        )
        workout.workoutBlocks = blocks
        return workout
    }

    private func strengthBlock(
        title: String = "Skulderpress",
        slug: String? = "athlth-native-overhead-press"
    ) -> WorkoutTemplateBlock {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise,
            title: title, exerciseSlug: slug,
            distanceMeters: nil, repetitions: 3,
            durationSeconds: nil, targetWeightKilograms: nil,
            loadNote: nil, notes: "Last set AMRAP",
            phase: .main, targetEffortRPE: 9,
            setCount: 5, restBetweenSetsSeconds: 180
        )
        block.targetRepsInReserve = 1
        return block
    }

    func testPlanExerciseIdentityLinksWithoutChangingPrescription() throws {
        let library = ExerciseLibraryStore().allExercises
        var session = workout(blocks: [strengthBlock()])
        let report = ATHLTHWorkoutExerciseBinding.bind(
            &session, library: library
        )
        XCTAssertTrue(report.isReady)
        XCTAssertEqual(report.linked, 1)
        let block = try XCTUnwrap(session.workoutBlocks?.first)
        let matched = try XCTUnwrap(library.first {
            $0.sourceIdentifier == "athlth-native-overhead-press"
        })
        XCTAssertEqual(block.exerciseID, matched.id)
        XCTAssertEqual(block.exerciseSlug, matched.sourceIdentifier)
        XCTAssertEqual(block.exerciseSnapshot?.name, matched.canonicalName)
        XCTAssertFalse(block.exerciseSnapshot?.instructions.isEmpty ?? true)
        XCTAssertEqual(block.setCount, 5)
        XCTAssertEqual(block.repetitions, 3)
        XCTAssertEqual(block.restBetweenSetsSeconds, 180)
        XCTAssertEqual(block.targetRepsInReserve, 1)
        XCTAssertEqual(block.targetEffortRPE, 9)
        XCTAssertEqual(block.notes, "Last set AMRAP")
        // The live strength engine must forward the library identity into
        // completed logs so "Last trained" and progression see this movement.
        let queue = StrengthWorkoutStore.strengthExerciseLogsFromBlocks([block])
        XCTAssertEqual(queue.first?.plannedExerciseID, matched.id)
        XCTAssertEqual(queue.first?.sets.count, 5)
    }

    func testEveryBundledGymCoachBlockCanBindBeforePlanActivation() {
        let library = ExerciseLibraryStore().allExercises
        for program in ATHLTHGymCoachStrengthLibrary.programs {
            for source in program.program.workouts {
                var session = ATHLTHGymCoachStrengthLibrary.plannedSession(
                    source, program: program, week: 1
                )
                let report = ATHLTHWorkoutExerciseBinding.bind(
                    &session, library: library
                )
                XCTAssertTrue(
                    report.isReady,
                    "Unlinked movement in \(program.slug): \(report.unresolved)"
                )
                XCTAssertTrue(session.workoutBlocks?.filter {
                    $0.kind == .exercise
                }.allSatisfy { $0.exerciseID != nil } == true)
            }
        }
    }

    func testLegacyUnidentifiedTextIsRetainedButNotAcceptedAsExecutable() {
        let library = ExerciseLibraryStore().allExercises
        var block = strengthBlock(
            title: "My Unique Movement", slug: nil
        )
        block.exerciseSnapshot = ExerciseSnapshot(
            name: "My Unique Movement", instructions: [],
            primaryMuscles: [], equipment: [], imageURL: nil
        )
        var session = workout(blocks: [block])
        let report = ATHLTHWorkoutExerciseBinding.bind(
            &session, library: library
        )
        XCTAssertFalse(report.isReady)
        XCTAssertEqual(report.unresolved, ["My Unique Movement"])
        XCTAssertEqual(session.workoutBlocks?.first?.title,
                       "My Unique Movement")
        XCTAssertNil(session.workoutBlocks?.first?.exerciseID)
        XCTAssertEqual(session.workoutBlocks?.first?.repetitions, 3)
    }

    func testOriginalOwnerIdentityNeverReplacedBySameNamedStockExercise() {
        let library = ExerciseLibraryStore().allExercises
        var step = strengthBlock(title: "Skulderpress")
        step.exerciseID = UUID() // The source UUID no longer exists here.
        var session = workout(blocks: [step])
        let report = ATHLTHWorkoutExerciseBinding.bind(
            &session, library: library
        )
        XCTAssertFalse(report.isReady)
        XCTAssertEqual(session.workoutBlocks?.first?.exerciseID,
                       step.exerciseID)
    }

    func testLegacyPlannedExerciseGetsCanonicalLibraryIdentity() throws {
        let library = ExerciseLibraryStore().allExercises
        let planned = PlannedExercise(
            id: UUID(), exerciseID: nil,
            embeddedExercise: ExerciseSnapshot(
                name: "Overhead Press", instructions: [],
                primaryMuscles: [], equipment: [], imageURL: nil
            ),
            sets: 5, reps: 3,
            targetWeightKilograms: nil, targetRPE: 9,
            restSeconds: 180, notes: nil
        )
        var session = workout(exercises: [planned])
        let report = ATHLTHWorkoutExerciseBinding.bind(
            &session, library: library
        )
        XCTAssertTrue(report.isReady)
        XCTAssertEqual(session.exercises.first?.exerciseID,
                       library.first {
                           $0.sourceIdentifier == "athlth-native-overhead-press"
                       }?.id)
        XCTAssertEqual(session.exercises.first?.id, planned.id)
        XCTAssertEqual(session.exercises.first?.sets, 5)
        XCTAssertEqual(session.exercises.first?.reps, 3)
        XCTAssertEqual(session.exercises.first?.restSeconds, 180)
    }

    func testCardioAndNotesDoNotRequireStrengthExerciseIdentity() {
        var session = workout(blocks: [
            WorkoutTemplateBlock(
                sequence: 1, kind: .note,
                title: "Warm up", exerciseSlug: nil,
                distanceMeters: nil, repetitions: nil,
                durationSeconds: 300, targetWeightKilograms: nil,
                loadNote: nil, notes: nil
            )
        ])
        let report = ATHLTHWorkoutExerciseBinding.bind(
            &session, library: []
        )
        XCTAssertTrue(report.isReady)
        XCTAssertEqual(report.linked, 0)
    }
}
