import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHIntervalWorkoutTests: XCTestCase {
    func testManualMainStartIsDefaultButAthleteCanOptIntoAutomatic() throws {
        var template = try XCTUnwrap(RunningWorkoutLibraryStore.builtInTemplates.first {
            $0.title == "4 × 4 intervaller"
        })
        let defaultTransfer = PlannedWorkoutWatchBuilder.runningTransfer(
            from: template, routeAlerts: .standard
        )
        XCTAssertNotEqual(defaultTransfer.autoStartMainAfterWarmup, true)
        template.autoStartMainAfterWarmup = true
        let automaticTransfer = PlannedWorkoutWatchBuilder.runningTransfer(
            from: template, routeAlerts: .standard
        )
        XCTAssertEqual(automaticTransfer.autoStartMainAfterWarmup, true)
        let data = try JSONEncoder().encode(automaticTransfer)
        XCTAssertEqual(try JSONDecoder().decode(
            WatchRunningWorkoutTransfer.self, from: data
        ).autoStartMainAfterWarmup, true)
    }

    func testStartMainCommandCarriesExactWorkoutAndStep() throws {
        let date = Date()
        let command = WatchWorkoutMirrorCommand(
            command: .advanceRunningStep,
            workoutStartedAt: date,
            expectedRunningStepIndex: 1,
            startMainAfterWarmup: true
        )
        let data = try JSONEncoder().encode(command)
        let restored = try JSONDecoder().decode(WatchWorkoutMirrorCommand.self, from: data)
        XCTAssertEqual(restored.command, .advanceRunningStep)
        XCTAssertEqual(restored.expectedRunningStepIndex, 1)
        XCTAssertEqual(restored.startMainAfterWarmup, true)
        XCTAssertEqual(restored.workoutStartedAt, date)
    }

    func testFourByFourHasOnlyThreeRecoveries() {
        let template = try! XCTUnwrap(RunningWorkoutLibraryStore.builtInTemplates.first {
            $0.title == "4 × 4 intervaller"
        })
        let transfer = PlannedWorkoutWatchBuilder.runningTransfer(
            from: template,
            routeAlerts: .standard
        )

        XCTAssertEqual(transfer.steps.count, 9) // warmup + 4 work + 3 rests + cooldown
        XCTAssertEqual(transfer.steps.filter { $0.phase == "work" }.count, 4)
        XCTAssertEqual(transfer.steps.filter { $0.phase == "recovery" }.count, 3)
        XCTAssertEqual(transfer.steps.last?.phase, "cooldown")
        XCTAssertEqual(template.estimatedDurationSeconds, 42 * 60)
    }

    func testGhostIgnoresEveryRecoveryAndRestartsEachRep() {
        var template = try! XCTUnwrap(RunningWorkoutLibraryStore.builtInTemplates.first {
            $0.title == "4 × 4 intervaller"
        })
        template.intervalGhostPaceSecondsPerKilometer = 300
        template.coachBrief = "Motiver meg og følg med på pulssone"
        template.blocks[1].work.intensity.heartRateZone = 4

        let steps = PlannedWorkoutWatchBuilder.runningTransfer(
            from: template,
            routeAlerts: .standard
        ).steps
        for step in steps where step.phase == "work" {
            XCTAssertEqual(step.targetHeartRateZone, 4)
            XCTAssertEqual(step.ghostPaceSecondsPerKilometer, 300)
            XCTAssertNotNil(step.coachBrief)
            XCTAssertEqual(
                ATHLTHIntervalGhostPacer.leadMeters(
                    step: step, elapsedSeconds: 60, distanceMeters: 220
                ) ?? 0,
                20, accuracy: 0.01
            )
        }
        for step in steps where step.phase != "work" {
            XCTAssertNil(step.ghostPaceSecondsPerKilometer)
            XCTAssertNil(ATHLTHIntervalGhostPacer.leadMeters(
                step: step, elapsedSeconds: 120, distanceMeters: 0
            ))
        }
    }

    func testPlannedPhaseZonesAndPacesReachWatchWithoutChangingTheIntervals() throws {
        var template = try XCTUnwrap(RunningWorkoutLibraryStore.builtInTemplates.first {
            $0.title == "4 × 4 intervaller"
        })
        template.blocks[0].work.intensity.kind = .pace
        template.blocks[0].work.intensity.paceMinSecondsPerKilometer = 420
        template.blocks[0].work.intensity.paceMaxSecondsPerKilometer = 420
        template.blocks[0].work.intensity.heartRateZone = 2
        template.blocks[1].work.intensity.kind = .pace
        template.blocks[1].work.intensity.paceMinSecondsPerKilometer = 300
        template.blocks[1].work.intensity.paceMaxSecondsPerKilometer = 300
        template.blocks[1].work.intensity.heartRateZone = 4
        template.blocks[1].recovery?.intensity.heartRateZone = 2

        // The workout recipe is Codable and survives the planner's persistence.
        let restored = try JSONDecoder().decode(
            RunningWorkoutTemplate.self,
            from: JSONEncoder().encode(template)
        )
        var planned = PlannedSession(
            id: UUID(), title: "Mølle 4 × 4",
            kind: .running, scheduledStart: nil,
            durationMinutes: nil, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: nil
        )
        planned.runningWorkout = restored
        planned.runningWorkouts = [restored]
        planned.workoutCategory = "treadmill"

        let transfer = PlannedWorkoutWatchBuilder.runningTransfer(
            from: planned, routeAlerts: .standard
        )
        let warmup = try XCTUnwrap(transfer.steps.first(where: { $0.phase == "warmup" }))
        XCTAssertEqual(warmup.targetHeartRateZone, 2)
        XCTAssertEqual(warmup.targetPaceMinSecondsPerKilometer ?? 0, 420, accuracy: 0.01)

        let effort = try XCTUnwrap(transfer.steps.first(where: { $0.phase == "work" }))
        XCTAssertEqual(effort.targetHeartRateZone, 4)
        // 12 km/t = 5:00 min/km, also used for treadmill.
        XCTAssertEqual(effort.targetPaceMinSecondsPerKilometer ?? 0, 300, accuracy: 0.01)

        let recovery = try XCTUnwrap(transfer.steps.first(where: { $0.phase == "recovery" }))
        XCTAssertEqual(recovery.targetHeartRateZone, 2)
        XCTAssertEqual(transfer.steps.count, 9)
    }

    func testCoachBriefOnlyAddsCuesDuringWork() {
        let work = WatchRunningWorkoutStep(
            id: UUID(), title: "Drag", measure: .time,
            distanceMeters: nil, durationSeconds: 240,
            intensityText: nil, phase: "work",
            targetHeartRateZone: 4, coachBrief: "Motiver meg og følg med på puls"
        )
        var rest = work
        rest.phase = "recovery"
        XCTAssertNotNil(ATHLTHIntervalCoachCue.phrase(for: work, norwegian: true))
        XCTAssertNil(ATHLTHIntervalCoachCue.phrase(for: rest, norwegian: true))
    }
}
