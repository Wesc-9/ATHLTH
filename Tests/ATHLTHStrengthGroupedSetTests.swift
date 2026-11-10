import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHStrengthGroupedSetTests: XCTestCase {
    private func exercise(
        _ reps: Int = 10, weight: Double = 25, sets: Int = 3
    ) -> WorkoutTemplateBlock {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Barbell Curl",
            exerciseSlug: "barbell-curl", distanceMeters: nil,
            repetitions: reps, durationSeconds: nil,
            targetWeightKilograms: weight, loadNote: nil,
            notes: nil, phase: .main
        )
        block.setCount = sets
        block.restBetweenSetsSeconds = 60
        return block
    }

    func testCircuitStrengthLogKeepsStationsRoundsAndPause() {
        let id = UUID()
        var squat = exercise(10, weight: 40)
        var press = exercise(8, weight: 30)
        var row = exercise(12, weight: 25)
        squat.title = "Squat"
        press.title = "Press"
        row.title = "Row"
        var blocks = [squat, press, row]
        for index in blocks.indices {
            blocks[index].groupID = id
            blocks[index].groupKind = .circuit
            blocks[index].groupRounds = 4
        }
        let logs = StrengthWorkoutStore.strengthExerciseLogsFromBlocks(blocks)
        XCTAssertEqual(logs.count, 3)
        XCTAssertTrue(logs.allSatisfy { $0.groupID == id && $0.groupStyle == .circuit })
        XCTAssertTrue(logs.allSatisfy { $0.sets.count == 4 })
        XCTAssertEqual(logs.map { $0.sets[0].plannedReps }, [10, 8, 12])
    }

    func testDropsetStrengthLogDoesNotBecomeThreeIndependentThreeSetExercises() {
        let id = UUID()
        var blocks = [exercise(10, weight: 25), exercise(8, weight: 20), exercise(6, weight: 15)]
        for index in blocks.indices {
            blocks[index].groupID = id
            blocks[index].groupKind = .dropSet
            blocks[index].groupRounds = 1
        }
        let logs = StrengthWorkoutStore.strengthExerciseLogsFromBlocks(blocks)
        XCTAssertEqual(logs.count, 3)
        XCTAssertTrue(logs.allSatisfy { $0.sets.count == 1 && $0.groupStyle == .dropSet })
        XCTAssertEqual(logs.map { $0.sets[0].plannedWeightKilograms }, [25, 20, 15])
        XCTAssertTrue(logs.allSatisfy { $0.sets[0].restSeconds == 0 })
    }

    func testAMRAPStrengthLogPreservesClockAndIdentityForWatchMirroring() {
        let id = UUID()
        var block = exercise(8, weight: 15)
        block.groupID = id
        block.groupKind = .amrap
        block.groupRounds = 20
        block.groupClockSeconds = 720
        let logs = StrengthWorkoutStore.strengthExerciseLogsFromBlocks([block])
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].groupID, id)
        XCTAssertEqual(logs[0].groupClockSeconds, 720)
        XCTAssertEqual(logs[0].groupStyle, .amrap)
        XCTAssertEqual(logs[0].sets.count, 1)
    }

    func testAMRAPCreatesAnotherRoundOnlyWhenTheEntirePreviousRoundIsDone() {
        let id = UUID()
        let started = Date(timeIntervalSince1970: 80_000)
        var stations = [exercise(8, weight: 15), exercise(12, weight: 8)]
        for index in stations.indices {
            stations[index].groupID = id
            stations[index].groupKind = .amrap
            stations[index].groupRounds = 20 // Old drafts must not impose a cap.
            stations[index].groupClockSeconds = 120
        }
        var logs = StrengthWorkoutStore.strengthExerciseLogsFromBlocks(stations)
        XCTAssertEqual(logs.map { $0.sets.count }, [1, 1])
        for index in logs.indices { logs[index].groupStartedAt = started }
        logs[0].sets[0].completedAt = started.addingTimeInterval(20)
        XCTAssertFalse(StrengthWorkoutStore.extendOpenEndedAMRAPGroupIfNeeded(
            exercises: &logs, groupID: id,
            at: started.addingTimeInterval(20)
        ))
        logs[1].sets[0].completedAt = started.addingTimeInterval(25)
        XCTAssertTrue(StrengthWorkoutStore.extendOpenEndedAMRAPGroupIfNeeded(
            exercises: &logs, groupID: id,
            at: started.addingTimeInterval(25)
        ))
        XCTAssertEqual(logs.map { $0.sets.count }, [2, 2])
        XCTAssertEqual(logs[0].sets[1].plannedReps, 8)
        XCTAssertNil(logs[0].sets[1].completedAt)
        XCTAssertFalse(StrengthWorkoutStore.extendOpenEndedAMRAPGroupIfNeeded(
            exercises: &logs, groupID: id,
            at: started.addingTimeInterval(26)
        ))
        logs[0].sets[1].completedAt = started.addingTimeInterval(119)
        logs[1].sets[1].completedAt = started.addingTimeInterval(119)
        XCTAssertFalse(StrengthWorkoutStore.extendOpenEndedAMRAPGroupIfNeeded(
            exercises: &logs, groupID: id,
            at: started.addingTimeInterval(120)
        ))
        XCTAssertEqual(logs.map { $0.sets.count }, [2, 2])
    }

    func testSingleStationAMRAPCanContinuePastOriginalRound() {
        let id = UUID()
        let started = Date(timeIntervalSince1970: 90_000)
        var source = exercise(10, weight: 5)
        source.groupID = id
        source.groupKind = .amrap
        source.groupClockSeconds = 120
        var logs = StrengthWorkoutStore.strengthExerciseLogsFromBlocks([source])
        logs[0].groupStartedAt = started
        logs[0].sets[0].completedAt = started.addingTimeInterval(15)
        XCTAssertTrue(StrengthWorkoutStore.extendOpenEndedAMRAPGroupIfNeeded(
            exercises: &logs, groupID: id,
            at: started.addingTimeInterval(15)
        ))
        XCTAssertEqual(logs[0].sets.count, 2)
    }

    func testEMOMResolvesMissedMinuteWithoutInventingVolume() throws {
        let id = UUID()
        let started = Date(timeIntervalSince1970: 100_000)
        var first = exercise(10, weight: 25)
        var second = exercise(12, weight: 10)
        first.groupID = id
        second.groupID = id
        first.groupKind = .emom
        second.groupKind = .emom
        first.groupRounds = 3
        second.groupRounds = 3
        first.groupClockSeconds = 60
        second.groupClockSeconds = 60
        var logs = StrengthWorkoutStore.strengthExerciseLogsFromBlocks([first, second])
        for index in logs.indices { logs[index].groupStartedAt = started }
        logs[0].sets[0].completedAt = started.addingTimeInterval(35)
        logs[0].sets[0].completedReps = 10
        logs[0].sets[0].completedWeightKilograms = 25

        let advanced = try XCTUnwrap(StrengthWorkoutStore.reconcileEMOMWindows(
            exercises: &logs, groupID: id,
            at: started.addingTimeInterval(121)
        ))
        XCTAssertEqual(advanced.skippedSlots, 1)
        XCTAssertEqual(advanced.nextExerciseIndex, 0)
        XCTAssertEqual(advanced.nextSetIndex, 1)
        XCTAssertTrue(logs[0].sets[0].isCompleted)
        XCTAssertFalse(logs[1].sets[0].isCompleted)
        XCTAssertTrue(logs[1].sets[0].isResolved)
        XCTAssertNotNil(logs[1].sets[0].skippedAt)
        XCTAssertEqual(logs[1].sets[0].volumeKilograms, 0)
        XCTAssertEqual(logs[1].skippedPlannedSetCount, 1)

        let again = try XCTUnwrap(StrengthWorkoutStore.reconcileEMOMWindows(
            exercises: &logs, groupID: id,
            at: started.addingTimeInterval(122)
        ))
        XCTAssertEqual(again.skippedSlots, 0)
        XCTAssertEqual(logs[1].skippedPlannedSetCount, 1)
        let restored = try JSONDecoder().decode(
            [StrengthExerciseLog].self,
            from: JSONEncoder().encode(logs)
        )
        XCTAssertTrue(restored[1].sets[0].isResolved)
        XCTAssertFalse(restored[1].sets[0].isCompleted)
    }

    func testGroupedStrengthStationTransitionIsSeparateFromRoundPause() {
        let id = UUID()
        var squat = exercise(10, weight: 40)
        var press = exercise(12, weight: 15)
        squat.groupID = id
        press.groupID = id
        squat.groupKind = .circuit
        press.groupKind = .circuit
        squat.groupRounds = 3
        press.groupRounds = 3
        squat.restBetweenSetsSeconds = 15
        press.restBetweenSetsSeconds = 15
        let logs = StrengthWorkoutStore.strengthExerciseLogsFromBlocks([squat, press])
        XCTAssertEqual(logs[0].sets.map(\.restSeconds), [15, 15, 15])
        XCTAssertEqual(logs[1].sets.map(\.restSeconds), [15, 15, 15])
    }

    func testGroupRoundPauseNeverAddsRecoveryAfterLastRound() {
        for kind in [WorkoutBlockGroupKind.superset, .circuit] {
            let id = UUID()
            var first = exercise(10, weight: 30)
            var second = exercise(8, weight: 20)
            first.groupID = id
            second.groupID = id
            first.groupKind = kind
            second.groupKind = kind
            first.groupRounds = 3
            second.groupRounds = 3
            var recovery = WorkoutTemplateBlock(
                sequence: 3, kind: .rest, title: "Rest between rounds",
                exerciseSlug: nil, distanceMeters: nil,
                repetitions: nil, durationSeconds: 60,
                targetWeightKilograms: nil, loadNote: nil, notes: nil,
                phase: .main
            )
            recovery.groupID = id
            recovery.groupKind = kind
            recovery.groupRounds = 3

            let output = StrengthWorkoutStore.strengthExerciseLogsFromBlocks(
                [first, second, recovery]
            )
            XCTAssertEqual(output.count, 2)
            XCTAssertNil(output[1].restSecondsOverride)
            XCTAssertEqual(output[1].sets.map(\.restSeconds), [60, 60, 0])
        }
    }

    func testOneParentCreatesIndividualExecutionSetsAndPauses() {
        var block = exercise()
        var targets = ATHLTHWorkoutSetExpansion.targets(for: block)
        targets[0].repetitions = 12
        targets[1].weightKilograms = 30
        targets[2].repetitions = 8
        block.individualSetTargets = targets

        let recipe = [block]
        XCTAssertEqual(recipe.count, 1, "The editor stores one parent exercise")
        let playback = recipe.expandedForExecution()
        XCTAssertEqual(playback.map(\.kind),
                       [.exercise, .rest, .exercise, .rest, .exercise])
        XCTAssertEqual(playback.filter { $0.kind == .exercise }.map(\.repetitions),
                       [12, 10, 8])
        XCTAssertEqual(playback.filter { $0.kind == .exercise }
                        .map(\.targetWeightKilograms), [25, 30, 25])
        XCTAssertEqual(playback.filter { $0.kind == .rest }.map(\.durationSeconds),
                       [60, 60])
    }

    func testIncreasingNumberOfSetsPreservesIndividualTargets() {
        var block = exercise()
        var targets = ATHLTHWorkoutSetExpansion.targets(for: block)
        targets[0].repetitions = 6
        block.individualSetTargets = targets
        block.setCount = 4
        let expanded = ATHLTHWorkoutSetExpansion.targets(for: block)
        XCTAssertEqual(expanded.count, 4)
        XCTAssertEqual(expanded[0].repetitions, 6)
        XCTAssertEqual(expanded[3].repetitions, 10)
    }

    func testRenumberAndCodableRoundTripKeepIndividualTargets() throws {
        var block = exercise()
        var targets = ATHLTHWorkoutSetExpansion.targets(for: block)
        targets[1].weightKilograms = 32.5
        block.individualSetTargets = targets

        let moved = ATHLTHWorkoutPhasePlacement.renumbered(block, sequence: 2)
        let decoded = try JSONDecoder().decode(
            WorkoutTemplateBlock.self,
            from: JSONEncoder().encode(moved)
        )
        XCTAssertEqual(decoded.sequence, 2)
        XCTAssertEqual(decoded.individualSetTargets?[1].weightKilograms, 32.5)
        XCTAssertEqual([decoded].expandedForExecution().count, 5)
    }

    func testLegacySplitSetsCollapseOnlyWhenRestMarkerMatches() {
        var base = exercise()
        base.setCount = nil
        base.restBetweenSetsSeconds = nil
        var second = ATHLTHWorkoutPhasePlacement.renumbered(base, sequence: 3)
        second.repetitions = 8
        var rest = WorkoutTemplateBlock(
            sequence: 2, kind: .rest, title: "Mellom sett",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 60,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .recovery
        )
        rest.editorDragID = UUID()
        let converted = ATHLTHWorkoutSetExpansion.collapsingLegacySets(
            in: [base, rest, second]
        )
        XCTAssertEqual(converted.count, 1)
        XCTAssertEqual(converted[0].setCount, 2)
        XCTAssertEqual(converted[0].individualSetTargets?.map(\.repetitions), [10, 8])

        var unrelatedRest = rest
        unrelatedRest.title = "Pause"
        XCTAssertEqual(ATHLTHWorkoutSetExpansion.collapsingLegacySets(
            in: [base, unrelatedRest, second]
        ).count, 3)
    }
}
