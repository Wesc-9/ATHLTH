import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutMainSectionTests: XCTestCase {
    @MainActor
    func testRunningPresetsNeverExposeStrengthOrCycling() {
        for preset in ATHLTHRunningExercisePreset.allCases {
            let blocks = preset.blocks(in: .main)
            XCTAssertTrue(blocks.contains(where: { $0.kind == .run }))
            XCTAssertTrue(blocks.allSatisfy {
                ($0.kind == .run && $0.cardioActivity == .running) ||
                    $0.kind == .rest
            })
        }
    }

    @MainActor
    func testSavedMainPhaseKeepsIntervalsWithoutWarmupOrCooldown() throws {
        let user = UUID()
        let workoutID = UUID()
        let warmup = try XCTUnwrap(ATHLTHRunningExercisePreset.progressive
            .blocks(in: .warmup).first)
        let main = ATHLTHRunningExercisePreset.fourByFour.blocks(in: .main)
        let cooldown = try XCTUnwrap(ATHLTHRunningExercisePreset.cooldown
            .blocks(in: .cooldown).first)

        let workout = makeWorkout(id: workoutID, kind: .running,
                                  blocks: [warmup] + main + [cooldown])
        XCTAssertTrue(ATHLTHWorkoutMainSectionLibrary.capture(workout, userID: user))
        let stored = try XCTUnwrap(ATHLTHWorkoutMainSectionLibrary.load(userID: user).first)
        XCTAssertEqual(stored.blocks.count, 2)
        XCTAssertTrue(stored.isRunningOnly)
        XCTAssertEqual(stored.blocks.map(\.durationSeconds), [240, 180])
        XCTAssertEqual(stored.blocks.map(\.groupRounds), [4, 4])

        let first = stored.blocksForReuse()
        let second = stored.blocksForReuse()
        XCTAssertEqual(first[0].groupID, first[1].groupID)
        XCTAssertNotEqual(first[0].groupID, second[0].groupID)
        XCTAssertNotEqual(first[0].editorDragID, second[0].editorDragID)
        XCTAssertTrue(first.allSatisfy { $0.resolvedPhase == .main })
    }

    @MainActor
    func testRepeatedSaveOfSameWorkoutUpdatesInsteadOfDuplicating() throws {
        let user = UUID()
        let workoutID = UUID()
        let original = makeWorkout(
            id: workoutID, kind: .running,
            blocks: ATHLTHRunningExercisePreset.easy.blocks(in: .main)
        )
        XCTAssertTrue(ATHLTHWorkoutMainSectionLibrary.capture(original, userID: user))
        XCTAssertTrue(ATHLTHWorkoutMainSectionLibrary.capture(original, userID: user))
        XCTAssertEqual(ATHLTHWorkoutMainSectionLibrary.load(userID: user).count, 1)

        var modified = original
        modified.title = "Updated main workout"
        XCTAssertTrue(ATHLTHWorkoutMainSectionLibrary.capture(modified, userID: user))
        let saved = try XCTUnwrap(ATHLTHWorkoutMainSectionLibrary.load(userID: user).first)
        XCTAssertEqual(saved.title, "Updated main workout")
        XCTAssertEqual(ATHLTHWorkoutMainSectionLibrary.load(userID: user).count, 1)
    }

    @MainActor
    func testStrengthMainSectionsAlsoPersistButStayOutOfRunPicker() throws {
        let user = UUID()
        let exercise = WorkoutTemplateBlock(
            sequence: 0, kind: .exercise, title: "Squats",
            exerciseSlug: nil, distanceMeters: nil, repetitions: 8,
            durationSeconds: nil, targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
        let workout = makeWorkout(
            id: UUID(), kind: .strength, blocks: [exercise]
        )
        XCTAssertTrue(ATHLTHWorkoutMainSectionLibrary.capture(workout, userID: user))
        let saved = try XCTUnwrap(ATHLTHWorkoutMainSectionLibrary.load(userID: user).first)
        XCTAssertEqual(saved.blocks.count, 1)
        XCTAssertFalse(saved.isRunningOnly)
    }

    private func makeWorkout(id: UUID, kind: WorkoutKind,
                             blocks: [WorkoutTemplateBlock]) -> PlannedSession {
        var workout = PlannedSession(
            id: id,
            title: "Main workout",
            kind: kind,
            scheduledStart: nil,
            durationMinutes: 30,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
        workout.workoutBlocks = blocks
        return workout
    }
}
