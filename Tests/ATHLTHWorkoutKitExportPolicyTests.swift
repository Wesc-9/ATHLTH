import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutKitExportPolicyTests: XCTestCase {
    private func recipe(steps: [WatchRunningWorkoutStep]) -> WatchPreparedWorkoutTransfer {
        WatchPreparedWorkoutTransfer(id: UUID(), title: "Intervals", summary: "",
            kind: .running, routeID: nil,
            runningWorkout: WatchRunningWorkoutTransfer(title: "Intervals", steps: steps),
            audioCoach: nil, updatedAt: Date())
    }

    private func step(phase: String = "work", seconds: Double = 60) -> WatchRunningWorkoutStep {
        WatchRunningWorkoutStep(id: UUID(), title: "Interval", measure: .time,
            distanceMeters: nil, durationSeconds: seconds, intensityText: nil, phase: phase)
    }

    func testPlainIntervalsCanExport() {
        XCTAssertTrue(ATHLTHWorkoutKitExportPolicy.canExport(recipe(steps: [
            step(phase: "warmup"), step(), step(phase: "recovery"), step(phase: "cooldown")
        ])))
    }

    func testRejectsUnrepresentableTargetsAndRoutes() {
        var target = step()
        target.targetHeartRateZone = 3
        XCTAssertFalse(ATHLTHWorkoutKitExportPolicy.canExport(recipe(steps: [target])))
        var routed = recipe(steps: [step()])
        routed.routeID = UUID()
        XCTAssertFalse(ATHLTHWorkoutKitExportPolicy.canExport(routed))
        XCTAssertFalse(ATHLTHWorkoutKitExportPolicy.canExport(recipe(steps: [step(seconds: .nan)])))
        XCTAssertFalse(ATHLTHWorkoutKitExportPolicy.canExport(recipe(steps: [step(), step(phase: "warmup")])))
    }
}
