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
    func testRunningIntervalPresetsCreateEveryEditableEffortAndPause() {
        let presets: [(ATHLTHRunningExercisePreset, Int)] = [
            (.strides, 6), (.hills, 8), (.fourByFour, 4),
            (.thirtyThirty, 20), (.fortyFiveFifteen, 15),
            (.fiveByThree, 5), (.sixByFourHundred, 6),
            (.fiveByOneKilometer, 5), (.shortIntervals, 10),
            (.fartlek, 10)
        ]
        for (preset, rounds) in presets {
            let blocks = preset.blocks(in: .main)
            XCTAssertEqual(blocks.count, rounds * 2, "\(preset)")
            XCTAssertEqual(blocks.expandedForExecution().count, rounds * 2)
            XCTAssertEqual(Set(blocks.map(\.editorDragID)).count, rounds * 2)
            let group = blocks.first?.groupID
            XCTAssertNotNil(group)
            XCTAssertTrue(blocks.allSatisfy {
                $0.groupID == group && $0.groupKind == .intervals &&
                    $0.groupRounds == 1
            })
            XCTAssertTrue(blocks.allSatisfy { $0.targetEffortRPE == nil })
            for index in blocks.indices {
                XCTAssertEqual(
                    index.isMultiple(of: 2),
                    !blocks[index].isRestOrActiveRecovery
                )
                XCTAssertEqual(blocks[index].resolvedPhase, .main)
            }
        }

        let fourByFour = ATHLTHRunningExercisePreset.fourByFour.blocks(in: .main)
        XCTAssertEqual(fourByFour.filter { !$0.isRestOrActiveRecovery }.count, 4)
        XCTAssertEqual(fourByFour.filter(\.isRestOrActiveRecovery).count, 4)
        XCTAssertEqual(fourByFour.reduce(0.0) {
            $0 + ($1.durationSeconds ?? 0)
        }, 28 * 60, accuracy: 0.01)
        XCTAssertEqual(ATHLTHWorkoutDurationEstimator.minutes(for: fourByFour), 30)
    }

    @MainActor
    func testNormalRunningAndTreadmillUseTheCorrectActivityEnvironment() throws {
        let normal = try XCTUnwrap(
            ATHLTHRunningExercisePreset.running.blocks(in: .main).first
        )
        XCTAssertEqual(normal.kind, .run)
        XCTAssertEqual(normal.cardioActivity, .running)
        XCTAssertEqual(normal.durationSeconds, 1_200)
        XCTAssertNotEqual(normal.isIndoor, true)
        XCTAssertNil(normal.treadmillInclinePercent)

        let treadmill = try XCTUnwrap(
            ATHLTHRunningExercisePreset.treadmill.blocks(in: .main).first
        )
        XCTAssertEqual(treadmill.kind, .run)
        XCTAssertEqual(treadmill.cardioActivity, .running)
        XCTAssertEqual(treadmill.durationSeconds, 1_200)
        XCTAssertEqual(treadmill.isIndoor, true)
        XCTAssertEqual(treadmill.treadmillInclinePercent, 0)
        XCTAssertEqual(treadmill.targetPaceSecondsPerKilometer, 360)
        XCTAssertEqual(treadmill.resolvedPhase, .main)
    }

    @MainActor
    func testThirtyThirtyAndOtherIntervalsKeepExactEffortsAndRecoveries() {
        let thirty = ATHLTHRunningExercisePreset.thirtyThirty.blocks(in: .main)
        XCTAssertEqual(thirty.count, 40)
        XCTAssertEqual(thirty.filter { !$0.isRestOrActiveRecovery }.count, 20)
        XCTAssertEqual(thirty.filter(\.isActiveRecovery).count, 20)
        XCTAssertTrue(thirty.allSatisfy { $0.durationSeconds == 30 })
        XCTAssertEqual(ATHLTHWorkoutDurationEstimator.minutes(for: thirty), 20)

        let fortyFive = ATHLTHRunningExercisePreset.fortyFiveFifteen.blocks(in: .main)
        XCTAssertEqual(fortyFive.count, 30)
        XCTAssertEqual(
            fortyFive.filter { !$0.isRestOrActiveRecovery }.compactMap(\.durationSeconds),
            Array(repeating: 45.0, count: 15)
        )
        XCTAssertEqual(
            fortyFive.filter(\.isActiveRecovery).compactMap(\.durationSeconds),
            Array(repeating: 15.0, count: 15)
        )
        XCTAssertEqual(ATHLTHWorkoutDurationEstimator.minutes(for: fortyFive), 15)

        let sixByFourHundred = ATHLTHRunningExercisePreset.sixByFourHundred
            .blocks(in: .main)
        XCTAssertEqual(sixByFourHundred.count, 12)
        XCTAssertTrue(sixByFourHundred.filter { $0.kind == .run }.allSatisfy {
            $0.distanceMeters == 400 && $0.durationSeconds == nil
        })
        XCTAssertTrue(sixByFourHundred.filter { $0.kind == .rest }.allSatisfy {
            $0.durationSeconds == 90 && $0.distanceMeters == nil
        })

        let fiveByOneK = ATHLTHRunningExercisePreset.fiveByOneKilometer
            .blocks(in: .main)
        XCTAssertEqual(fiveByOneK.count, 10)
        XCTAssertTrue(fiveByOneK.filter { $0.kind == .run }.allSatisfy {
            $0.distanceMeters == 1_000 && $0.durationSeconds == nil
        })
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
        XCTAssertEqual(stored.blocks.count, 8)
        XCTAssertTrue(stored.isRunningOnly)
        XCTAssertEqual(
            stored.blocks.compactMap(\.durationSeconds),
            Array(repeating: [240.0, 180.0], count: 4).flatMap { $0 }
        )
        XCTAssertNotNil(stored.blocks.first?.groupID)
        XCTAssertTrue(stored.blocks.allSatisfy {
            $0.groupID == stored.blocks.first?.groupID &&
                $0.groupKind == .intervals && $0.groupRounds == 1
        })

        let first = stored.blocksForReuse()
        let second = stored.blocksForReuse()
        XCTAssertEqual(first.filter { !$0.isRestOrActiveRecovery }.count, 4)
        XCTAssertEqual(first.filter(\.isActiveRecovery).count, 4)
        XCTAssertEqual(
            ATHLTHIntervalRecipeEditing.forEditing(first).count, 8
        )
        XCTAssertNotEqual(first.first?.groupID, second.first?.groupID)
        XCTAssertEqual(first.count, second.count)
        XCTAssertNotEqual(first[0].editorDragID, first[1].editorDragID)
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
