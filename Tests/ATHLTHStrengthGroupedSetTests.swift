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

    func testModernSupersetRecipeOverridesStaleLegacyExerciseArray() {
        let id = UUID()
        let legacy = PlannedExercise(
            id: UUID(), exerciseID: nil,
            embeddedExercise: ExerciseSnapshot(
                name: "Legacy Bench",
                instructions: [], primaryMuscles: [], equipment: [],
                imageURL: nil
            ),
            sets: 3, reps: 10, targetWeightKilograms: 25,
            targetRPE: nil, restSeconds: 60, notes: nil
        )
        var first = exercise(10, weight: 40)
        var second = exercise(12, weight: 25)
        first.title = "Modern Squat"
        second.title = "Modern Row"
        first.groupID = id
        second.groupID = id
        first.groupKind = .superset
        second.groupKind = .superset
        first.groupRounds = 2
        second.groupRounds = 2
        var workout = PlannedSession(
            id: UUID(), title: "Grouped workout", kind: .strength,
            scheduledStart: nil, durationMinutes: 20,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [legacy], notes: nil
        )
        workout.workoutBlocks = [first, second]
        let store = StrengthWorkoutStore()
        store.start(
            session: workout, watchSessionID: nil,
            trackingMode: .simple, captureDevice: .iPhone
        )
        XCTAssertEqual(store.activeWorkout?.exercises.count, 2)
        XCTAssertEqual(store.activeWorkout?.exercises.map { $0.exercise.name },
                       ["Modern Squat", "Modern Row"])
        XCTAssertEqual(store.activeWorkout?.exercises.map(\.groupID), [id, id])
        XCTAssertEqual(store.activeWorkout?.exercises.map { $0.sets.count }, [2, 2])
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
        XCTAssertEqual(logs[1].auditedSkippedSets, 1,
                       "A retained EMOM slot and the legacy counter are the same skip.")

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
        XCTAssertEqual(restored[1].auditedSkippedSets, 1)

        // Historical checkpoints with a larger already-persisted counter
        // must remain readable and must not add the timestamp a second time.
        var older = restored[1]
        older.skippedPlannedSetCount = 2
        XCTAssertEqual(older.auditedSkippedSets, 2)
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

    func testOneStationEMOMSkipCannotBeRepeatedOrLoggedAsCompleted() throws {
        let id = UUID()
        var block = exercise(8, weight: 20, sets: 1)
        block.groupID = id
        block.groupKind = .emom
        block.groupRounds = 1
        block.groupClockSeconds = 60
        var plan = PlannedSession(
            id: UUID(), title: "EMOM idempotence", kind: .strength,
            scheduledStart: nil, durationMinutes: 5,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        plan.workoutBlocks = [block]
        let store = StrengthWorkoutStore()
        store.start(
            session: plan, watchSessionID: nil,
            trackingMode: .advanced, captureDevice: .iPhone
        )
        let originalWorkoutID = try XCTUnwrap(store.activeWorkout?.id)
        let originalSetID = try XCTUnwrap(store.currentSet?.id)
        XCTAssertEqual(store.currentExercise?.groupStyle, .emom)

        XCTAssertTrue(store.skipCurrentSet())
        XCTAssertFalse(store.skipCurrentSet(),
                       "The same skipped minute must not be skipped twice.")
        store.completeCurrentDraftSet()

        let recorded = try XCTUnwrap(store.activeWorkout)
        let slot = try XCTUnwrap(recorded.exercises.first?.sets.first)
        XCTAssertEqual(recorded.id, originalWorkoutID)
        XCTAssertEqual(slot.id, originalSetID)
        XCTAssertNil(slot.completedAt)
        XCTAssertNotNil(slot.skippedAt)
        XCTAssertEqual(recorded.totalCompletedSets, 0)
        XCTAssertEqual(recorded.exercises.first?.auditedSkippedSets, 1)
    }



    func testGroupedSkipPreservesRoundAndStationIdentity() throws {
        for style in [WorkoutBlockGroupKind.superset, .circuit, .dropSet] {
            let groupID = UUID()
            var first = exercise(10, weight: 30, sets: 2)
            var second = exercise(8, weight: 20, sets: 2)
            for block in [0, 1] {
                if block == 0 {
                    first.groupID = groupID
                    first.groupKind = style
                    first.groupRounds = style == .dropSet ? 1 : 2
                } else {
                    second.groupID = groupID
                    second.groupKind = style
                    second.groupRounds = style == .dropSet ? 1 : 2
                }
            }
            var plan = PlannedSession(
                id: UUID(), title: "Skip group station", kind: .strength,
                scheduledStart: nil, durationMinutes: 15,
                targetDistanceKilometers: nil,
                targetPaceSecondsPerKilometer: nil,
                routeID: nil, exercises: [], notes: nil
            )
            plan.workoutBlocks = [first, second]
            let store = StrengthWorkoutStore()
            store.start(
                session: plan, watchSessionID: nil,
                trackingMode: .advanced, captureDevice: .iPhone
            )
            let originalWorkoutID = try XCTUnwrap(store.activeWorkout?.id)
            let originalIDs = try XCTUnwrap(
                store.activeWorkout?.exercises.map { $0.sets.map(\.id) }
            )
            XCTAssertEqual(store.activeWorkout?.exercises.count, 2)

            XCTAssertTrue(store.skipCurrentSet(), "Skip failed in \(style)")
            let after = try XCTUnwrap(store.activeWorkout)
            XCTAssertEqual(after.id, originalWorkoutID)
            XCTAssertEqual(after.exercises.map { $0.sets.map(\.id) }, originalIDs,
                           "Skipping a station must not renumber rounds.")
            XCTAssertTrue(after.exercises[0].sets[0].isResolved)
            XCTAssertFalse(after.exercises[0].sets[0].isCompleted)
            XCTAssertEqual(after.exercises[0].auditedSkippedSets, 1)
            XCTAssertEqual(after.exercises[0].skippedPlannedSetCount, 1)
            XCTAssertEqual(after.totalCompletedSets, 0)
            XCTAssertEqual(store.currentExercise?.id, after.exercises[1].id,
                           "Next grouped station should be selected.")
        }
    }



    func testSkippingLastGroupedSlotAllowsExplicitMoveToNextExercise() throws {
        let id = UUID()
        var grouped = exercise(10, weight: 25, sets: 1)
        grouped.groupID = id
        grouped.groupKind = .superset
        grouped.groupRounds = 1
        var next = exercise(12, weight: 15, sets: 1)
        next.title = "Next exercise after group"
        var plan = PlannedSession(
            id: UUID(), title: "Group followed by exercise",
            kind: .strength, scheduledStart: nil,
            durationMinutes: 10,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        plan.workoutBlocks = [grouped, next]
        let store = StrengthWorkoutStore()
        store.start(
            session: plan, watchSessionID: nil,
            trackingMode: .advanced, captureDevice: .iPhone
        )
        let skippedSet = try XCTUnwrap(store.currentSet?.id)
        let selectedExercise = try XCTUnwrap(store.currentExercise?.id)
        XCTAssertTrue(store.skipCurrentSet())
        XCTAssertTrue(store.currentExerciseAllSetsCompleted)
        XCTAssertTrue(store.hasNextExercise)
        XCTAssertFalse(store.selectSetForNow(
            exerciseID: selectedExercise, setID: skippedSet
        ), "An intentionally skipped slot must not become a new pending set.")

        store.moveToNextExercise()
        XCTAssertEqual(store.currentExercise?.exercise.name, "Next exercise after group")
        XCTAssertFalse(store.currentSet?.isResolved ?? true)
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 0)
        XCTAssertEqual(store.activeWorkout?.exercises.first?.auditedSkippedSets, 1)
        XCTAssertEqual(store.activeWorkout?.exercises.first?.sets.first?.id, skippedSet)
    }



    func testEarlyEMOMRestCommandDoesNotClearCountdownOrStartNextStation() throws {
        let groupID = UUID()
        var first = exercise(8, weight: 20, sets: 1)
        var second = exercise(10, weight: 15, sets: 1)
        for index in 0..<2 {
            if index == 0 {
                first.groupID = groupID
                first.groupKind = .emom
                first.groupRounds = 1
                first.groupClockSeconds = 60
            } else {
                second.groupID = groupID
                second.groupKind = .emom
                second.groupRounds = 1
                second.groupClockSeconds = 60
            }
        }
        var plan = PlannedSession(
            id: UUID(), title: "Timed station gate", kind: .strength,
            scheduledStart: nil, durationMinutes: 3,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        plan.workoutBlocks = [first, second]
        let store = StrengthWorkoutStore()
        store.start(
            session: plan, watchSessionID: nil,
            trackingMode: .advanced, captureDevice: .iPhone
        )
        XCTAssertTrue(store.skipCurrentSet())
        XCTAssertEqual(store.currentExercise?.id, store.activeWorkout?.exercises[1].id)
        XCTAssertFalse(store.canCompleteCurrentStrengthMode())

        store.addRest(seconds: 30)
        let originalRestDeadline = try XCTUnwrap(store.restEndsAt)
        let pendingID = try XCTUnwrap(store.currentSet?.id)
        XCTAssertFalse(store.skipRest())
        XCTAssertEqual(store.restEndsAt, originalRestDeadline)
        XCTAssertEqual(store.currentSet?.id, pendingID)
        XCTAssertNil(store.currentSetEffortClock)
        XCTAssertNil(store.currentTimedSetCountdown)
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 0)
    }

    func testRestBlocksCountdownAndInvalidNextDoesNotDiscardRest() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        let timed = Exercise(
            id: UUID(), origin: .publicCatalog, ownerID: nil,
            name: "Wall Sit", instructions: [], primaryMuscles: ["Quadriceps"],
            secondaryMuscles: [], equipment: [], imageURL: nil,
            isVisibleOutsideOwnerLibrary: true
        )
        store.appendExercise(
            timed, sets: 1, reps: nil, targetKind: .time,
            targetDurationSeconds: 45, restSeconds: 0
        )
        store.addRest(seconds: 20)
        let originalRest = try XCTUnwrap(store.restEndsAt)
        store.startOrResumeTimedSet()
        XCTAssertNil(store.currentTimedSetCountdown)
        XCTAssertNil(store.currentSetEffortClock)

        store.moveToNextExercise()
        XCTAssertEqual(store.restEndsAt, originalRest,
                       "An invalid next-exercise action cannot dismiss rest.")

        XCTAssertTrue(store.skipRest())
        XCTAssertNil(store.restEndsAt)
        store.startOrResumeTimedSet()
        XCTAssertNotNil(store.currentTimedSetCountdown)
        XCTAssertNotNil(store.currentSetEffortClock)
        XCTAssertEqual(store.currentSet?.plannedDurationSeconds, 45)
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 0)
    }

    func testEMOMExpiryClearsStaleClockWhenMovingIntoNextExercise() throws {
        let groupID = UUID()
        var emom = exercise(8, weight: 12, sets: 1)
        emom.groupID = groupID
        emom.groupKind = .emom
        emom.groupRounds = 1
        emom.groupClockSeconds = 60
        var next = exercise(10, weight: 20, sets: 1)
        next.title = "Next planned station"
        var plan = PlannedSession(
            id: UUID(), title: "EMOM followed by strength", kind: .strength,
            scheduledStart: nil, durationMinutes: 5,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        plan.workoutBlocks = [emom, next]
        let store = StrengthWorkoutStore()
        store.start(session: plan, watchSessionID: nil)
        let started = try XCTUnwrap(store.currentExercise?.groupStartedAt)
        let parentID = try XCTUnwrap(store.activeWorkout?.id)
        store.startCurrentSetEffort()
        XCTAssertNotNil(store.currentSetEffortClock)
        store.addRest(seconds: 15)

        XCTAssertEqual(
            store.reconcileCurrentEMOM(at: started.addingTimeInterval(65)), 1
        )
        XCTAssertEqual(store.activeWorkout?.id, parentID)
        XCTAssertEqual(store.currentExercise?.exercise.name, "Next planned station")
        XCTAssertNil(store.restEndsAt)
        XCTAssertNil(store.currentSetEffortClock)
        XCTAssertNil(store.currentTimedSetCountdown)
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 0)
        XCTAssertEqual(store.activeWorkout?.exercises.first?.auditedSkippedSets, 1)
    }



    func testWatchSnapshotDoesNotDoubleCountPreservedGroupSkips() throws {
        let groupID = UUID()
        var grouped = exercise(8, weight: 20, sets: 1)
        grouped.groupID = groupID
        grouped.groupKind = .emom
        grouped.groupRounds = 1
        grouped.groupClockSeconds = 60
        var plan = PlannedSession(
            id: UUID(), title: "Watch totals in EMOM", kind: .strength,
            scheduledStart: nil, durationMinutes: 5,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        plan.workoutBlocks = [grouped]
        let store = StrengthWorkoutStore()
        store.start(session: plan, watchSessionID: nil)
        XCTAssertEqual(store.watchSnapshot?.totalSets, 1)
        XCTAssertTrue(store.skipCurrentSet())
        XCTAssertEqual(store.watchSnapshot?.totalSets, 1)
        XCTAssertEqual(store.watchSnapshot?.skippedSets, 1)
        XCTAssertEqual(store.watchSnapshot?.completedSets, 0)
        XCTAssertEqual(store.activeWorkout?.exercises.first?.auditedSkippedSets, 1)
    }

    func testOfflineWatchRestCommandsRespectOriginalSetAndRestStart() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        let base = Date().addingTimeInterval(-200)
        let workoutID = try XCTUnwrap(store.activeWorkout?.id)
        store.addRest(seconds: 45, at: base)
        let restDeadline = try XCTUnwrap(store.restEndsAt)

        func command(_ kind: WatchStrengthCommandKind, sentAt: Date,
                     setIndex: Int = 0, addSeconds: Int? = nil) -> WatchStrengthCommand {
            WatchStrengthCommand(
                id: UUID(), workoutID: workoutID, kind: kind,
                reps: nil, weightKilograms: nil, restSeconds: nil,
                addRestSeconds: addSeconds, sentAt: sentAt,
                exerciseIndex: 0, setIndex: setIndex
            )
        }
        // A command for another set, or one sent before this rest started,
        // must not extend or dismiss the current rest.
        store.replayOfflineWatchCommands([
            command(.addRest, sentAt: base.addingTimeInterval(20),
                    setIndex: 1, addSeconds: 30),
            command(.skipRest, sentAt: base.addingTimeInterval(-35)),
            command(.addRest, sentAt: base.addingTimeInterval(-20),
                    addSeconds: 90)
        ])
        XCTAssertEqual(store.restEndsAt, restDeadline)
        XCTAssertNil(store.currentSetEffortClock)

        store.replayOfflineWatchCommands([
            command(.skipRest, sentAt: base.addingTimeInterval(25))
        ])
        XCTAssertFalse(store.isResting)
        XCTAssertEqual(store.currentSetEffortClock?.startedAt,
                       base.addingTimeInterval(25))
    }

    func testOfflineWatchCompletionAndRestUseOriginalEventDates() throws {
        let store = StrengthWorkoutStore()
        store.startFreestyle(watchSessionID: nil)
        let squat = Exercise(
            id: UUID(), origin: .publicCatalog, ownerID: nil,
            name: "Squat", instructions: [], primaryMuscles: ["Quadriceps"],
            secondaryMuscles: [], equipment: [], imageURL: nil,
            isVisibleOutsideOwnerLibrary: true
        )
        store.appendExercise(squat, sets: 2, reps: 8, restSeconds: 40)
        let workoutID = try XCTUnwrap(store.activeWorkout?.id)
        let completedAt = Date().addingTimeInterval(-135)
        let completed = WatchStrengthCommand(
            id: UUID(), workoutID: workoutID, kind: .completeSetWithoutDetails,
            reps: nil, weightKilograms: nil, restSeconds: 40,
            addRestSeconds: nil, sentAt: completedAt,
            exerciseIndex: 0, setIndex: 0
        )
        store.replayOfflineWatchCommands([completed])
        XCTAssertEqual(store.activeWorkout?.exercises.first?.sets.first?.completedAt,
                       completedAt)
        XCTAssertEqual(store.restStartedAt, completedAt)
        XCTAssertEqual(store.restEndsAt, completedAt.addingTimeInterval(40))
        XCTAssertEqual(store.currentSetIndex, 1)

        let resumedAt = completedAt.addingTimeInterval(22)
        let next = WatchStrengthCommand(
            id: UUID(), workoutID: workoutID, kind: .skipRest,
            reps: nil, weightKilograms: nil, restSeconds: nil,
            addRestSeconds: nil, sentAt: resumedAt,
            exerciseIndex: 0, setIndex: 1
        )
        store.replayOfflineWatchCommands([next])
        XCTAssertEqual(store.activeWorkout?.exercises.first?.sets.first?
            .actualRestAfterSeconds, 22, accuracy: 0.01)
        XCTAssertEqual(store.currentSetEffortClock?.startedAt, resumedAt)
        XCTAssertNil(store.restEndsAt)
        XCTAssertEqual(store.activeWorkout?.totalCompletedSets, 1)
    }


}
