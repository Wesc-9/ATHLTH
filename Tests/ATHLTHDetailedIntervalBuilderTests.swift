import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHDetailedIntervalBuilderTests: XCTestCase {
    func testIndividualTargetEditSurvivesSerializationAndWatchProjection() throws {
        var plan = template()
        let original = plan.blocks[1].resolvedWork(at: 3)
        var edit = original
        edit.durationSeconds = 47
        edit.intensity.paceMinSecondsPerKilometer = 232
        edit.intensity.paceMaxSecondsPerKilometer = 232
        let updated = ATHLTHRunningTargetEditing.preservingAdditionalTargets(from: original, in: edit)
        plan.blocks[1].repetitionOverrides = [RunningRepetitionOverride(
            repetition: 3, work: updated,
            recovery: .time(35, intensity: .easy))]
        let restored = try JSONDecoder().decode(RunningWorkoutTemplate.self,
                                               from: JSONEncoder().encode(plan))
        let transfer = PlannedWorkoutWatchBuilder.runningTransfer(from: restored, routeAlerts: .standard)
        let work = transfer.steps.filter { $0.phase == "work" }
        let recovery = transfer.steps.filter { $0.phase == "recovery" }
        XCTAssertEqual(work.map(\.durationSeconds), [240, 240, 47, 240])
        XCTAssertEqual(work.map(\.targetPaceMinSecondsPerKilometer), [300, 300, 232, 300])
        XCTAssertEqual(recovery.map(\.durationSeconds), [120, 120, 35])
        XCTAssertEqual(work[2].targetHeartRateZone, 4)
    }

    private func template() -> RunningWorkoutTemplate {
        let hard = RunningIntensityTarget(
            kind: .pace,
            paceMinSecondsPerKilometer: 300,
            paceMaxSecondsPerKilometer: 300,
            heartRateZone: 4,
            rpe: nil
        )
        let main = RunningWorkoutBlock(
            kind: .work,
            title: "Interval",
            repetitions: 4,
            work: .time(240, intensity: hard),
            recovery: .time(120, intensity: .easy),
            repetitionOverrides: [
                RunningRepetitionOverride(
                    repetition: 3,
                    work: .time(255, intensity: hard),
                    recovery: .time(180, intensity: .easy)
                )
            ]
        )
        return RunningWorkoutTemplate(
            id: UUID(), title: "Detailed 4×4", type: .intervals,
            summary: "Individual reps", blocks: [
                RunningWorkoutBlock(kind: .warmup, title: "Jog", work: .time(600, intensity: .easy)),
                main,
                RunningWorkoutBlock(kind: .cooldown, title: "Jog down", work: .time(600, intensity: .easy))
            ],
            routeID: nil, isBuiltIn: false,
            createdAt: Date(), updatedAt: Date()
        )
    }

    func testThirdPauseCanBeLongerWithoutChangingOtherPauses() {
        let plan = template()
        let steps = PlannedWorkoutWatchBuilder.runningTransfer(
            from: plan, routeAlerts: .standard
        ).steps
        XCTAssertEqual(steps.count, 9)
        XCTAssertEqual(steps.filter { $0.phase == "work" }.count, 4)
        XCTAssertEqual(steps.filter { $0.phase == "recovery" }.count, 3)
        XCTAssertEqual(steps[2].durationSeconds, 120)
        XCTAssertEqual(steps[4].durationSeconds, 120)
        XCTAssertEqual(steps[6].durationSeconds, 180)
        XCTAssertEqual(steps[5].durationSeconds, 255)
        XCTAssertEqual(steps.last?.phase, "cooldown")
        XCTAssertEqual(plan.estimatedDurationSeconds ?? -1, 2_595, accuracy: 0.001)
    }

    func testPerDragPaceAndPulseTargetReachesWatch() {
        var plan = template()
        plan.intervalGhostPaceSecondsPerKilometer = 300
        plan.blocks[1].repetitionOverrides?.append(
            RunningRepetitionOverride(repetition: 2, ghostPaceSecondsPerKilometer: 285)
        )
        let steps = PlannedWorkoutWatchBuilder.runningTransfer(
            from: plan, routeAlerts: .standard
        ).steps
        XCTAssertEqual(steps[1].targetHeartRateZone, 4)
        XCTAssertEqual(steps[1].ghostPaceSecondsPerKilometer, 300)
        XCTAssertEqual(steps[3].ghostPaceSecondsPerKilometer, 285)
        XCTAssertNil(steps[2].ghostPaceSecondsPerKilometer)
        XCTAssertNil(steps[0].ghostPaceSecondsPerKilometer)
        XCTAssertNil(steps[8].ghostPaceSecondsPerKilometer)
    }

    func testRecoveryGhostDoesNotPenalizeSlowRunning() {
        var plan = template()
        plan.intervalGhostPaceSecondsPerKilometer = 300
        plan.intervalGhostFollowRecovery = true
        plan.intervalGhostRecoverySlowdownPercent = 25
        let steps = PlannedWorkoutWatchBuilder.runningTransfer(
            from: plan, routeAlerts: .standard
        ).steps
        XCTAssertTrue(ATHLTHIntervalGhostPacer.followsRecovery(
            step: steps[2], observedPaceSecondsPerKilometer: 420
        ))
        XCTAssertFalse(ATHLTHIntervalGhostPacer.followsRecovery(
            step: steps[2], observedPaceSecondsPerKilometer: 315
        ))
        XCTAssertNil(ATHLTHIntervalGhostPacer.leadMeters(
            step: steps[2], elapsedSeconds: 60, distanceMeters: 100
        ))
        XCTAssertEqual(ATHLTHIntervalGhostPacer.leadMeters(
            step: steps[1], elapsedSeconds: 120, distanceMeters: 450
        ) ?? -1, 50, accuracy: 0.001)
    }

    func testWarmupCooldownAndIndividualEffortTargetsReachWatch() {
        let warm = RunningIntensityTarget(
            kind: .pace, paceMinSecondsPerKilometer: 420,
            paceMaxSecondsPerKilometer: 420, heartRateZone: 2, rpe: nil
        )
        let cooldown = RunningIntensityTarget(
            kind: .pace, paceMinSecondsPerKilometer: 480,
            paceMaxSecondsPerKilometer: 480, heartRateZone: 1, rpe: nil
        )
        let second = RunningIntensityTarget(
            kind: .pace, paceMinSecondsPerKilometer: 265,
            paceMaxSecondsPerKilometer: 265, heartRateZone: 5, rpe: nil
        )
        var plan = template()
        plan.blocks[0].work = .time(600, intensity: warm)
        plan.blocks[2].work = .time(480, intensity: cooldown)
        var overrides = plan.blocks[1].repetitionOverrides ?? []
        overrides.append(RunningRepetitionOverride(
            repetition: 2, work: .time(240, intensity: second)
        ))
        plan.blocks[1].repetitionOverrides = overrides

        let steps = PlannedWorkoutWatchBuilder.runningTransfer(
            from: plan, routeAlerts: .standard
        ).steps
        XCTAssertEqual(steps.first?.targetPaceMinSecondsPerKilometer, 420)
        XCTAssertEqual(steps.first?.targetHeartRateZone, 2)
        XCTAssertEqual(steps[3].targetPaceMinSecondsPerKilometer, 265)
        XCTAssertEqual(steps[3].targetHeartRateZone, 5)
        XCTAssertEqual(steps.last?.targetPaceMinSecondsPerKilometer, 480)
        XCTAssertEqual(steps.last?.targetHeartRateZone, 1)
    }

    func testManualWarmupFinishesBeforeExplicitMainStart() {
        var plan = template()
        plan.blocks.insert(RunningWorkoutBlock(
            kind: .recovery,
            title: "Pause før hoveddel",
            work: .time(90, intensity: .easy)
        ), at: 1)
        plan.autoAdvanceTimedSteps = false
        // Manual main start replaces the obsolete timed preparation pause.
        let transfer = PlannedWorkoutWatchBuilder.runningTransfer(
            from: plan, routeAlerts: .standard
        )
        XCTAssertEqual(transfer.autoAdvanceTimedSteps, false)
        XCTAssertNotEqual(transfer.autoStartMainAfterWarmup, true)
        XCTAssertEqual(transfer.steps[0].phase, "warmup")
        XCTAssertEqual(transfer.steps[1].phase, "work")
        XCTAssertFalse(transfer.steps.contains {
            $0.title == "Pause før hoveddel"
        })
    }

    func testAutomaticMainStartRetainsExplicitPreparationRecovery() {
        var plan = template()
        plan.blocks.insert(RunningWorkoutBlock(
            kind: .recovery,
            title: "Pause før hoveddel",
            work: .time(90, intensity: .easy)
        ), at: 1)
        plan.autoStartMainAfterWarmup = true
        let transfer = PlannedWorkoutWatchBuilder.runningTransfer(
            from: plan, routeAlerts: .standard
        )
        XCTAssertEqual(transfer.autoStartMainAfterWarmup, true)
        XCTAssertEqual(transfer.steps[0].phase, "warmup")
        XCTAssertEqual(transfer.steps[1].phase, "recovery")
        XCTAssertEqual(transfer.steps[1].durationSeconds, 90)
        XCTAssertEqual(transfer.steps[2].phase, "work")
    }

    func testOldIntervalPlansStillAdvanceTimedPhasesAutomatically() {
        let legacy = template()
        XCTAssertNil(legacy.autoAdvanceTimedSteps)
        let transfer = PlannedWorkoutWatchBuilder.runningTransfer(
            from: legacy, routeAlerts: .standard
        )
        XCTAssertNil(transfer.autoAdvanceTimedSteps)
        XCTAssertEqual(transfer.autoAdvanceTimedSteps ?? true, true)
    }

    func testOldWorkoutDefaultsStayValid() throws {
        let existing = RunningWorkoutBlock(
            kind: .work, title: "Legacy",
            repetitions: 3, work: .time(120),
            recovery: .time(60)
        )
        let restored = try JSONDecoder().decode(
            RunningWorkoutBlock.self,
            from: JSONEncoder().encode(existing)
        )
        XCTAssertNil(restored.repetitionOverrides)
        XCTAssertEqual(restored.resolvedWork(at: 3).durationSeconds, 120)
        XCTAssertEqual(restored.resolvedRecovery(after: 2)?.durationSeconds, 60)
        XCTAssertNil(restored.resolvedRecovery(after: 3))
    }
}
