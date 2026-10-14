import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHIntervalWorkoutTests: XCTestCase {
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
