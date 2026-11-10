import Foundation
import XCTest
@testable import ATHLTH

final class WorkoutTemplateTimelineTests: XCTestCase {
    private func exercise(_ title: String) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: title,
            exerciseSlug: "test", distanceMeters: nil,
            repetitions: 8, durationSeconds: nil,
            targetWeightKilograms: 40,
            loadNote: nil, notes: nil, phase: .main
        )
    }

    private func running() -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Run",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 120,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
    }

    private func recovery() -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 2, kind: .rest, title: "Recovery",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 60,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .recovery
        )
    }

    func testThreeSetsInsertRecoveryOnlyBetweenSets() {
        var block = exercise("Squat")
        block.setCount = 3
        block.restBetweenSetsSeconds = 90
        let steps = [block].expandedForExecution()

        XCTAssertEqual(steps.count, 5)
        XCTAssertEqual(steps.map(\.kind), [
            .exercise, .rest, .exercise, .rest, .exercise
        ])
        XCTAssertEqual(steps.filter { $0.kind == .rest }.compactMap(\.durationSeconds), [90, 90])
        XCTAssertEqual(steps.filter { $0.kind == .exercise }.compactMap(\.repetitions), [8, 8, 8])
        XCTAssertEqual(steps.map(\.sequence), [1, 2, 3, 4, 5])
        XCTAssertEqual(Set(steps.map(\.id)).count, steps.count)
    }

    func testSupersetRunsEachExerciseInOrderForEveryRound() {
        let group = UUID()
        var squat = exercise("Squat")
        var pushup = exercise("Push-up")
        squat.groupID = group
        squat.groupKind = .superset
        squat.groupRounds = 3
        pushup.groupID = group
        pushup.groupKind = .superset
        pushup.groupRounds = 3

        let steps = [squat, pushup].expandedForExecution()
        XCTAssertEqual(steps.count, 6)
        XCTAssertEqual(steps.map { $0.title.components(separatedBy: " · ")[0] },
                       ["Squat", "Push-up", "Squat", "Push-up", "Squat", "Push-up"])
        XCTAssertTrue(steps.allSatisfy { $0.groupID == nil })
    }

    func testSupersetOptionalRoundRestRunsBetweenButNotAfterFinalRound() {
        let group = UUID()
        var squat = exercise("Squat")
        var bench = exercise("Bench press")
        var row = exercise("Row")
        var pause = recovery()
        squat.groupID = group
        squat.groupKind = .superset
        squat.groupRounds = 3
        bench.groupID = group
        bench.groupKind = .superset
        bench.groupRounds = 3
        row.groupID = group
        row.groupKind = .superset
        row.groupRounds = 3
        pause.groupID = group
        pause.groupKind = .superset
        pause.groupRounds = 3

        let steps = [squat, bench, row, pause].expandedForExecution()
        XCTAssertEqual(steps.count, 11)
        XCTAssertEqual(steps.map(\.kind), [
            .exercise, .exercise, .exercise, .rest,
            .exercise, .exercise, .exercise, .rest,
            .exercise, .exercise, .exercise
        ])
        XCTAssertEqual(steps.map { $0.title.components(separatedBy: " · ")[0] }, [
            "Squat", "Bench press", "Row", "Recovery",
            "Squat", "Bench press", "Row", "Recovery",
            "Squat", "Bench press", "Row"
        ])
        XCTAssertEqual(
            steps.filter { $0.kind == .rest }.compactMap(\.durationSeconds),
            [60, 60]
        )
        XCTAssertEqual(
            ATHLTHWorkoutDurationEstimator.minutes(for: [squat, bench, row, pause]),
            10
        )
    }

    func testCircuitThreeStationsKeepOrderAndSkipLastRoundPause() throws {
        let id = UUID()
        let squat = exercise("Squat")
        let row = exercise("Row")
        var plank = exercise("Plank")
        let rest = recovery()

        plank.repetitions = nil
        plank.durationSeconds = 45

        var stations = [squat, row, plank, rest]
        for index in stations.indices {
            stations[index].groupID = id
            stations[index].groupKind = .circuit
            stations[index].groupRounds = 3
        }

        // The entire circuit survives template storage and reopening.
        let saved = try JSONEncoder().encode(stations)
        let decoded = try JSONDecoder().decode(
            [WorkoutTemplateBlock].self, from: saved
        )
        XCTAssertEqual(decoded, stations)
        XCTAssertTrue(decoded.allSatisfy {
            $0.groupKind == .circuit && $0.groupRounds == 3
        })

        let executed = decoded.expandedForExecution()
        XCTAssertEqual(executed.count, 11)
        XCTAssertEqual(executed.map(\.kind), [
            .exercise, .exercise, .exercise, .rest,
            .exercise, .exercise, .exercise, .rest,
            .exercise, .exercise, .exercise
        ])
        XCTAssertEqual(
            executed.map { $0.title.components(separatedBy: " · ")[0] },
            [
                "Squat", "Row", "Plank", "Recovery",
                "Squat", "Row", "Plank", "Recovery",
                "Squat", "Row", "Plank"
            ]
        )
        XCTAssertEqual(executed.filter { $0.kind == .rest }.count, 2)
        XCTAssertEqual(
            ATHLTHWorkoutDurationEstimator.previewSeconds(for: decoded),
            537
        )
    }

    func testSingleRoundCircuitHasNoTrailingRest() {
        let groupID = UUID()
        var squat = exercise("Squat")
        var row = exercise("Row")
        var pushup = exercise("Push-up")
        var pause = recovery()

        squat.groupID = groupID
        row.groupID = groupID
        pushup.groupID = groupID
        pause.groupID = groupID
        squat.groupKind = .circuit
        row.groupKind = .circuit
        pushup.groupKind = .circuit
        pause.groupKind = .circuit
        squat.groupRounds = 1
        row.groupRounds = 1
        pushup.groupRounds = 1
        pause.groupRounds = 1

        let steps = [squat, row, pushup, pause].expandedForExecution()
        XCTAssertEqual(steps.map(\.kind), [.exercise, .exercise, .exercise])
        XCTAssertEqual(steps.count, 3)
    }

    func testCircuitAndSupersetRemainDistinctStrengthGroupKinds() {
        XCTAssertEqual(WorkoutBlockGroupKind.circuit.rawValue, "circuit")
        XCTAssertEqual(WorkoutBlockGroupKind.circuit.minimumStrengthExercises, 3)
        XCTAssertEqual(WorkoutBlockGroupKind.superset.minimumStrengthExercises, 2)
        XCTAssertEqual(WorkoutBlockGroupKind.intervals.minimumStrengthExercises, 0)
        XCTAssertTrue(WorkoutBlockGroupKind.circuit.isStrengthGroup)
        XCTAssertTrue(WorkoutBlockGroupKind.superset.isStrengthGroup)
        XCTAssertFalse(WorkoutBlockGroupKind.intervals.isStrengthGroup)
    }

    func testEMOMUsesFixedMinuteSlotsRatherThanRepTime() throws {
        let id = UUID()
        var squat = exercise("Squat")
        var pushup = exercise("Push-up")
        squat.groupID = id
        pushup.groupID = id
        squat.groupKind = .emom
        pushup.groupKind = .emom
        squat.groupRounds = 10
        pushup.groupRounds = 10
        squat.groupClockSeconds = 60
        pushup.groupClockSeconds = 60

        let source = [squat, pushup]
        let decoded = try JSONDecoder().decode(
            [WorkoutTemplateBlock].self, from: JSONEncoder().encode(source)
        )
        XCTAssertEqual(decoded, source)
        let executed = decoded.expandedForExecution()
        XCTAssertEqual(executed.count, 20)
        XCTAssertEqual(executed.first?.executionGroupKind, .emom)
        XCTAssertEqual(executed.last?.executionRound, 10)
        XCTAssertEqual(executed.last?.executionStationCount, 2)
        XCTAssertEqual(ATHLTHWorkoutDurationEstimator.previewSeconds(for: source), 1200)
    }

    func testAMRAPHasOneRealTimeCapNotTwentyRoundsOfRepEstimates() {
        let id = UUID()
        var squat = exercise("Squat")
        var pushup = exercise("Push-up")
        squat.groupID = id
        pushup.groupID = id
        squat.groupKind = .amrap
        pushup.groupKind = .amrap
        squat.groupRounds = 20
        pushup.groupRounds = 20
        squat.groupClockSeconds = 720
        pushup.groupClockSeconds = 720

        let steps = [squat, pushup].expandedForExecution()
        XCTAssertEqual(steps.count, 40)
        XCTAssertEqual(steps.first?.executionGroupClockSeconds, 720)
        XCTAssertEqual(ATHLTHWorkoutDurationEstimator.previewSeconds(for: [squat, pushup]), 720)
    }

    func testDropsetStagesRetainIndependentLoadsWithoutRecovery() throws {
        let id = UUID()
        var heavy = exercise("Biceps curl")
        var medium = exercise("Biceps curl")
        var light = exercise("Biceps curl")
        heavy.groupID = id
        medium.groupID = id
        light.groupID = id
        heavy.groupKind = .dropSet
        medium.groupKind = .dropSet
        light.groupKind = .dropSet
        heavy.groupRounds = 1
        medium.groupRounds = 1
        light.groupRounds = 1
        heavy.repetitions = 10
        medium.repetitions = 8
        light.repetitions = 6
        heavy.targetWeightKilograms = 25
        medium.targetWeightKilograms = 20
        light.targetWeightKilograms = 15

        let source = [heavy, medium, light]
        let saved = try JSONDecoder().decode([WorkoutTemplateBlock].self,
                                             from: JSONEncoder().encode(source))
        let steps = saved.expandedForExecution()
        XCTAssertEqual(steps.count, 3)
        XCTAssertEqual(steps.map(\.targetWeightKilograms), [25, 20, 15])
        XCTAssertEqual(steps.map(\.repetitions), [10, 8, 6])
        XCTAssertEqual(steps.filter { $0.kind == .rest }.count, 0)
        XCTAssertEqual(steps.map(\.executionGroupKind), [.dropSet, .dropSet, .dropSet])
    }

    func testStructuredAMRAPGrowsOneRoundAtATimeBeforeDeadline() {
        let id = UUID()
        var pushup = exercise("Push-up")
        var squat = exercise("Squat")
        pushup.groupID = id
        squat.groupID = id
        pushup.groupKind = .amrap
        squat.groupKind = .amrap
        pushup.groupRounds = 20 // Previous fixed allocation is intentionally ignored.
        squat.groupRounds = 20
        pushup.groupClockSeconds = 180
        squat.groupClockSeconds = 180
        let followUp = exercise("Cool-down")
        let initial = ATHLTHStructuredAMRAPProgression.initialSteps(
            from: [pushup, squat, followUp]
        )
        XCTAssertEqual(initial.count, 3)
        XCTAssertEqual(initial[0].executionRound, 1)
        XCTAssertNil(ATHLTHStructuredAMRAPProgression.appendingNextRound(
            to: initial, after: 0,
            startedAt: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 110)
        ))
        let started = Date(timeIntervalSince1970: 100)
        let second = ATHLTHStructuredAMRAPProgression.appendingNextRound(
            to: initial, after: 1, startedAt: started,
            now: started.addingTimeInterval(30)
        )
        XCTAssertEqual(second?.count, 5)
        XCTAssertEqual(second?[2].executionRound, 2)
        XCTAssertEqual(second?[3].executionRound, 2)
        XCTAssertEqual(second?[4].title, "Cool-down")
        XCTAssertNil(ATHLTHStructuredAMRAPProgression.appendingNextRound(
            to: second ?? initial, after: 3, startedAt: started,
            now: started.addingTimeInterval(180)
        ))
    }

    func testStructuredStrengthRuntimeCheckpointKeepsClockAndActualResults() throws {
        let id = UUID()
        var stage = exercise("Squat")
        stage.groupID = id
        stage.groupKind = .emom
        stage.groupRounds = 3
        stage.groupClockSeconds = 60
        let first = ATHLTHStructuredAMRAPProgression.initialSteps(from: [stage])
        let started = Date(timeIntervalSince1970: 100_000)
        let actual = StructuredWorkoutStepResult(
            stepID: first[0].id, title: "Squat",
            groupKind: .emom, round: 1, repetitions: 10,
            weightKilograms: 30, elapsedSeconds: 30, completed: true
        )
        let state = ATHLTHStructuredWorkoutCheckpoint(
            workoutID: UUID(), savedAt: started.addingTimeInterval(32),
            startedAt: started, stepEnteredAt: started.addingTimeInterval(30),
            currentIndex: 1, completedIDs: [first[0].id],
            results: [first[0].id: actual], modeStarts: [id: started],
            executionBlocks: first, emomWaiting: false,
            timedOutGroups: [], enteredReps: 10, enteredWeight: "30"
        )
        let read = try JSONDecoder().decode(
            ATHLTHStructuredWorkoutCheckpoint.self,
            from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(read.executionBlocks.map(\.executionRound), [1, 2, 3])
        XCTAssertEqual(read.results[first[0].id]?.repetitions, 10)
        XCTAssertEqual(read.modeStarts[id], started)
        XCTAssertEqual(read.currentIndex, 1)
    }

    func testStrengthModesNeverAvailableInCardioOrWellnessEditors() {
        XCTAssertTrue(ATHLTHStrengthModeAvailability.canCreate(
            initialActivity: .strength, containsStrength: false
        ))
        XCTAssertTrue(ATHLTHStrengthModeAvailability.canCreate(
            initialActivity: nil, containsStrength: true
        ))
        XCTAssertFalse(ATHLTHStrengthModeAvailability.canCreate(
            initialActivity: nil, containsStrength: false
        ))
        for category: ATHLTHPlannedWorkoutType in [.running, .walking, .cycling, .mobility] {
            XCTAssertFalse(ATHLTHStrengthModeAvailability.canCreate(
                initialActivity: category, containsStrength: true
            ))
            XCTAssertFalse(ATHLTHStrengthModeAvailability.canCreate(
                initialActivity: category, containsStrength: false
            ))
        }
    }

    func testEMOMClockPolicyRejectsEarlyAndMissedSlots() {
        let started = Date(timeIntervalSince1970: 100_000)
        func allowed(_ second: Double, station: Int) -> Bool {
            ATHLTHStrengthModeClockPolicy.permitsCompletion(
                modeRaw: "emom", startedAt: started, clockSeconds: 60,
                roundIndex: 0, stationIndex: station, stationCount: 3,
                at: started.addingTimeInterval(second)
            )
        }
        XCTAssertTrue(allowed(25, station: 0))
        XCTAssertFalse(allowed(60, station: 0))
        XCTAssertFalse(allowed(40, station: 1))
        XCTAssertTrue(allowed(62, station: 1))
        XCTAssertEqual(ATHLTHStrengthModeClockPolicy.remainingSeconds(
            modeRaw: "emom", startedAt: started, clockSeconds: 60,
            roundIndex: 0, stationIndex: 1, stationCount: 3,
            at: started.addingTimeInterval(85)
        ), 35)
    }

    func testAMRAPClockPolicyStopsAtDeadlineButPreservesPriorEfforts() {
        let started = Date(timeIntervalSince1970: 100_000)
        func allowed(_ second: Double) -> Bool {
            ATHLTHStrengthModeClockPolicy.permitsCompletion(
                modeRaw: "amrap", startedAt: started, clockSeconds: 720,
                roundIndex: 0, stationIndex: 0, stationCount: 3,
                at: started.addingTimeInterval(second)
            )
        }
        XCTAssertTrue(allowed(719))
        XCTAssertFalse(allowed(720))
        XCTAssertFalse(allowed(810))
        XCTAssertTrue(ATHLTHStrengthModeClockPolicy.permitsCompletion(
            modeRaw: nil, startedAt: nil, clockSeconds: nil,
            roundIndex: 0, stationIndex: 0, stationCount: 1,
            at: started
        ))
    }

    func testIntervalRepeatsRunAndRecoveryButSkipsFinalRecovery() {
        let id = UUID()
        var run = running()
        var rest = recovery()
        run.groupID = id
        run.groupKind = .intervals
        run.groupRounds = 4
        rest.groupID = id
        rest.groupKind = .intervals
        rest.groupRounds = 4

        let steps = [run, rest].expandedForExecution()
        XCTAssertEqual(steps.count, 7)
        XCTAssertEqual(steps.filter { $0.kind == .run }.count, 4)
        XCTAssertEqual(steps.filter { $0.kind == .rest }.count, 3)
        XCTAssertEqual(steps.last?.kind, .run)
    }

    func testLegacyRecipeDecodesAndRunsOnce() throws {
        let saved = exercise("Legacy")
        let data = try JSONEncoder().encode(saved)
        let restored = try JSONDecoder().decode(WorkoutTemplateBlock.self, from: data)
        XCTAssertNil(restored.setCount)
        XCTAssertNil(restored.groupID)
        XCTAssertEqual([restored].expandedForExecution().count, 1)
    }

    func testDragIdentityIsNotPartOfPersistedRecipeEquality() throws {
        var original = exercise("Hip thrust")
        original.editorDragID = UUID()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkoutTemplateBlock.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(original.hashValue, decoded.hashValue)
        XCTAssertNotEqual(original.editorDragID, decoded.editorDragID)

        // A new drag token must never change the underlying workout.
        original.editorDragID = UUID()
        XCTAssertEqual(original, decoded)
    }

    func testGroupFieldsSurviveEncoding() throws {
        var block = exercise("Bench press")
        block.groupID = UUID()
        block.groupKind = .superset
        block.groupRounds = 4
        let saved = try JSONEncoder().encode(block)
        let restored = try JSONDecoder().decode(WorkoutTemplateBlock.self, from: saved)
        XCTAssertEqual(restored.groupID, block.groupID)
        XCTAssertEqual(restored.groupKind, .superset)
        XCTAssertEqual(restored.groupRounds, 4)
    }
    func testIntensityTargetsSurviveEncodingAndExpansion() throws {
        var cycling = WorkoutTemplateBlock(
            sequence: 1, kind: .note, title: "Sykling",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 600,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .warmup
        )
        cycling.activityTag = "cycling"
        cycling.targetHeartRateZone = 2
        cycling.targetEffortRPE = 4

        let encoded = try JSONEncoder().encode(cycling)
        let decoded = try JSONDecoder().decode(WorkoutTemplateBlock.self, from: encoded)
        XCTAssertEqual(decoded, cycling)
        XCTAssertTrue(decoded.targetText?.contains("RPE 4/10") == true)
        let executed = try XCTUnwrap([decoded].expandedForExecution().first)
        XCTAssertEqual(executed.durationSeconds, 600)
        XCTAssertEqual(executed.targetEffortRPE, 4)
        XCTAssertEqual(executed.targetHeartRateZone, 2)
        XCTAssertEqual(executed.phase, .warmup)
    }

    func testLegacyBlockWithoutEffortTargetDecodes() throws {
        let old = try JSONEncoder().encode(exercise("Legacy squat"))
        let decoded = try JSONDecoder().decode(WorkoutTemplateBlock.self, from: old)
        XCTAssertNil(decoded.targetEffortRPE)
    }

}
