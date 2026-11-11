import XCTest
@testable import ATHLTH

final class ATHLTHLiveIntervalPresentationTests: XCTestCase {
    private func step(_ phase: String, seconds: Double = 240) -> WatchRunningWorkoutStep {
        WatchRunningWorkoutStep(
            id: UUID(),
            title: phase,
            measure: .time,
            distanceMeters: nil,
            durationSeconds: seconds,
            intensityText: nil,
            phase: phase
        )
    }

    func testFourByFourShowsOneOfFourNotOneOfNine() {
        let steps = [step("warmup", seconds: 600)] +
            (0..<4).flatMap { index in
                index == 3
                    ? [step("work")]
                    : [step("work"), step("recovery", seconds: 120)]
            } + [step("cooldown", seconds: 600)]
        XCTAssertEqual(steps.count, 9)

        let first = ATHLTHRunningIntervalPosition.resolve(
            steps: steps, currentIndex: 1
        )
        XCTAssertEqual(first?.ordinal, 1)
        XCTAssertEqual(first?.total, 4)
        XCTAssertEqual(first?.isRecovery, false)

        let rest = ATHLTHRunningIntervalPosition.resolve(
            steps: steps, currentIndex: 2
        )
        XCTAssertEqual(rest?.ordinal, 1)
        XCTAssertEqual(rest?.nextOrdinal, 2)
        XCTAssertEqual(rest?.total, 4)
        XCTAssertEqual(rest?.isRecovery, true)

        let finalWork = ATHLTHRunningIntervalPosition.resolve(
            steps: steps, currentIndex: 7
        )
        XCTAssertEqual(finalWork?.ordinal, 4)
        XCTAssertEqual(finalWork?.total, 4)
        XCTAssertNil(ATHLTHRunningIntervalPosition.resolve(
            steps: steps, currentIndex: 0
        ))
    }

    func testNormalRouteDoesNotInventAnIntervalCounter() {
        XCTAssertNil(ATHLTHRunningIntervalPosition.resolve(
            steps: [
                step("warmup", seconds: 600),
                WatchRunningWorkoutStep(
                    id: UUID(), title: "Follow route", measure: .open,
                    distanceMeters: nil, durationSeconds: nil,
                    intensityText: nil, phase: "work"
                )
            ],
            currentIndex: 1
        ))
    }

    func testQuickRouteWarmupReusesPlannedRunningStepTargets() {
        var config = ATHLTHRouteWarmupConfiguration()
        config.enabled = true
        config.durationMinutes = 10
        config.targetPaceSecondsPerKilometer = 375
        config.targetHeartRateZone = 2
        config.autoStartMain = false

        let transfer = config.runningTransfer(
            title: "Route", routeAlerts: .standard,
            autoPauseEnabled: true
        )
        XCTAssertEqual(transfer?.steps.map(\.phase), ["warmup", "work"])
        XCTAssertEqual(transfer?.steps.first?.durationSeconds, 600)
        XCTAssertEqual(transfer?.steps.first?.targetPaceMinSecondsPerKilometer, 375)
        XCTAssertEqual(transfer?.steps.first?.targetHeartRateZone, 2)
        XCTAssertEqual(transfer?.autoStartMainAfterWarmup, false)
    }
}
