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
    @MainActor
    func testWatchReceivesEveryEmbeddedTreadmillPhaseWithoutNewRecording() throws {
        let planned = try plannedHybrid()
        let parts = try XCTUnwrap(ATHLTHHybridWorkoutLaunchPlan.parts(for: planned))
        let store = StrengthWorkoutStore()
        let watchID = UUID()
        XCTAssertTrue(store.startPlannedHybrid(
            session: planned, validatedParts: parts, watchSessionID: watchID,
            trackingMode: .advanced, captureDevice: .appleWatch
        ))
        let workoutID = try XCTUnwrap(store.activeWorkout?.id)
        let run = try XCTUnwrap(store.activeWorkout?.exercises.first {
            $0.isEmbeddedRunningInterval == true && $0.sets.count > 1
        })
        XCTAssertTrue(store.selectExerciseForNow(run.id))
        let watch = try XCTUnwrap(store.watchSnapshot)
        let exercise = try XCTUnwrap(watch.exerciseQueue?.first {
            $0.index == watch.exerciseIndex
        })
        let plans = try XCTUnwrap(exercise.setPlans)
        XCTAssertEqual(watch.workoutID, workoutID)
        XCTAssertEqual(watch.plannedSessionID, planned.id)
        XCTAssertEqual(store.activeWorkout?.watchSessionID, watchID)
        XCTAssertEqual(exercise.isEmbeddedRunningInterval, true)
        XCTAssertEqual(plans.count, run.sets.count)
        for (plan, source) in zip(plans, run.sets) {
            XCTAssertEqual(plan.durationSeconds, source.plannedDurationSeconds)
            XCTAssertEqual(plan.hybridPhaseTitle, source.hybridPhaseTitle)
            XCTAssertEqual(plan.hybridPhaseKind, source.hybridPhaseKind)
            XCTAssertEqual(plan.hybridTargetHeartRateZone, source.hybridTargetHeartRateZone)
            XCTAssertEqual(plan.hybridTargetPaceSecondsPerKilometer,
                           source.hybridTargetPaceSecondsPerKilometer)
        }
        XCTAssertEqual(watch.embeddedRunningTargetPaceSecondsPerKilometer,
                       run.sets[0].hybridTargetPaceSecondsPerKilometer)
    }

    @MainActor
    func testWatchCompletesOnlyActiveEmbeddedRunningIntervals() throws {
        let planned = try plannedHybrid()
        let parts = try XCTUnwrap(ATHLTHHybridWorkoutLaunchPlan.parts(for: planned))
        let store = StrengthWorkoutStore()
        XCTAssertTrue(store.startPlannedHybrid(
            session: planned, validatedParts: parts, watchSessionID: UUID(),
            trackingMode: .advanced, captureDevice: .appleWatch
        ))
        let run = try XCTUnwrap(store.activeWorkout?.exercises.first {
            $0.isEmbeddedRunningInterval == true
        })
        XCTAssertTrue(store.selectExerciseForNow(run.id))
        var watch = try XCTUnwrap(store.watchSnapshot)
        let beganAt = Date(timeIntervalSince1970: 1_000)
        watch.timedSetCountdown = WatchTimedStrengthCountdown(
            targetSeconds: 60, secondsAtPause: 60, resumedAt: beganAt
        )
        let before = beganAt.addingTimeInterval(59)
        let after = beganAt.addingTimeInterval(61)

        XCTAssertFalse(ATHLTHHybridWatchIntervalPolicy.shouldAutoAdvance(
            watch, workoutState: .running, at: before
        ))
        XCTAssertTrue(ATHLTHHybridWatchIntervalPolicy.shouldAutoAdvance(
            watch, workoutState: .running, at: after
        ))
        XCTAssertFalse(ATHLTHHybridWatchIntervalPolicy.shouldAutoAdvance(
            watch, workoutState: .paused, at: after
        ))
        watch.inputMode = .iPhone
        XCTAssertFalse(ATHLTHHybridWatchIntervalPolicy.shouldAutoAdvance(
            watch, workoutState: .running, at: after
        ))
        watch.inputMode = .both
        watch.isResting = true
        XCTAssertFalse(ATHLTHHybridWatchIntervalPolicy.shouldAutoAdvance(
            watch, workoutState: .running, at: after
        ))
        watch.isResting = false
        watch.isEmbeddedRunningInterval = false
        XCTAssertFalse(ATHLTHHybridWatchIntervalPolicy.shouldAutoAdvance(
            watch, workoutState: .running, at: after
        ))
    }

    @MainActor
    func testOfflineWatchPauseResumePreservesEventClock() throws {
        let planned = try plannedHybrid()
        let parts = try XCTUnwrap(ATHLTHHybridWorkoutLaunchPlan.parts(for: planned))
        let store = StrengthWorkoutStore()
        XCTAssertTrue(store.startPlannedHybrid(
            session: planned, validatedParts: parts, watchSessionID: UUID(),
            trackingMode: .advanced, captureDevice: .appleWatch
        ))
        let run = try XCTUnwrap(store.activeWorkout?.exercises.first {
            $0.isEmbeddedRunningInterval == true
        })
        XCTAssertTrue(store.selectExerciseForNow(run.id))
        let initial = try XCTUnwrap(store.currentTimedSetCountdown)
        let started = try XCTUnwrap(initial.resumedAt)
        let stopped = started.addingTimeInterval(12)
        let resumed = started.addingTimeInterval(120)

        store.pauseTimedSet(at: stopped)
        let paused = try XCTUnwrap(store.currentTimedSetCountdown)
        XCTAssertNil(paused.resumedAt)
        XCTAssertEqual(paused.remaining(at: resumed),
                       Double(initial.targetSeconds - 12), accuracy: 0.001)
        store.startOrResumeTimedSet(at: resumed)
        let continued = try XCTUnwrap(store.currentTimedSetCountdown)
        XCTAssertEqual(continued.resumedAt, resumed)
        XCTAssertEqual(continued.remaining(at: resumed),
                       Double(initial.targetSeconds - 12), accuracy: 0.001)
        XCTAssertEqual(store.activeWorkout?.plannedSessionID, planned.id)
    }

    @MainActor
    func testHybridPhaseClockHasOneOwnerAcrossPhoneAndWatch() throws {
        let session = try plannedHybrid()
        let parts = try XCTUnwrap(ATHLTHHybridWorkoutLaunchPlan.parts(for: session))

        let watchStore = StrengthWorkoutStore()
        XCTAssertTrue(watchStore.startPlannedHybrid(
            session: session, validatedParts: parts,
            watchSessionID: UUID(), trackingMode: .advanced,
            captureDevice: .appleWatch
        ))
        let watchRun = try XCTUnwrap(watchStore.activeWorkout?.exercises.first {
            $0.isEmbeddedRunningInterval == true
        })
        XCTAssertTrue(watchStore.selectExerciseForNow(watchRun.id))
        XCTAssertFalse(watchStore.controlsEmbeddedHybridClockOnIPhone)
        let watchClock = try XCTUnwrap(watchStore.currentTimedSetCountdown)
        let watchStart = try XCTUnwrap(watchClock.resumedAt)
        watchStore.advanceEmbeddedIntervalIfNeeded(
            at: watchStart.addingTimeInterval(TimeInterval(watchClock.targetSeconds + 2))
        )
        // Watch-owned intervals are committed exclusively by Watch commands.
        XCTAssertEqual(watchStore.activeWorkout?.totalCompletedSets, 0)

        let phoneStore = StrengthWorkoutStore()
        XCTAssertTrue(phoneStore.startPlannedHybrid(
            session: session, validatedParts: parts,
            watchSessionID: nil, trackingMode: .advanced,
            captureDevice: .iPhone
        ))
        let phoneRun = try XCTUnwrap(phoneStore.activeWorkout?.exercises.first {
            $0.isEmbeddedRunningInterval == true
        })
        XCTAssertTrue(phoneStore.selectExerciseForNow(phoneRun.id))
        XCTAssertTrue(phoneStore.controlsEmbeddedHybridClockOnIPhone)
        let phoneClock = try XCTUnwrap(phoneStore.currentTimedSetCountdown)
        let phoneStart = try XCTUnwrap(phoneClock.resumedAt)
        phoneStore.advanceEmbeddedIntervalIfNeeded(
            at: phoneStart.addingTimeInterval(TimeInterval(phoneClock.targetSeconds + 2))
        )
        XCTAssertGreaterThanOrEqual(phoneStore.activeWorkout?.totalCompletedSets ?? 0, 1)
    }

    func testWatchHybridPhaseRecordsElapsedNotJustPlannedDuration() {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        var timer = WatchTimedStrengthCountdown(
            targetSeconds: 240, secondsAtPause: 240, resumedAt: start
        )
        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(90)), 90, accuracy: 0.001)
        let pausedAt = start.addingTimeInterval(90)
        timer.secondsAtPause = timer.remaining(at: pausedAt)
        timer.resumedAt = nil
        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(600)), 90, accuracy: 0.001)
        timer.resumedAt = start.addingTimeInterval(600)
        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(750)), 240, accuracy: 0.001)
        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(775)), 265, accuracy: 0.001)
    }

}
