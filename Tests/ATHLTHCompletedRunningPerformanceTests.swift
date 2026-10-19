import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCompletedRunningPerformanceTests: XCTestCase {
    private func sample(_ index: Int, phase: String = "main",
                        meters: Double = 800) -> ATHLTHRecordedRunningStep {
        ATHLTHRecordedRunningStep(
            index: index, title: "Intervall", phase: phase,
            activeSeconds: 240, distanceMeters: meters,
            isUserReported: false,
            targetPaceSecondsPerKilometer: 240
        )
    }

    func testIncompleteWorkoutsAndDuplicateSplitsNeverQualify() {
        XCTAssertFalse(ATHLTHCompletedRunningPerformance.validFullRecording(
            [sample(0)], expectedCount: 9
        ))
        XCTAssertFalse(ATHLTHCompletedRunningPerformance.validFullRecording(
            [sample(0), sample(0)], expectedCount: 2
        ))
    }

    func testRecordedSpeedIsIndependentOfTargetPace() throws {
        let steps = [
            sample(0, phase: "warmup"),
            sample(1),
            sample(2, phase: "recovery", meters: 200),
            sample(3),
            sample(4, phase: "cooldown")
        ]
        XCTAssertTrue(ATHLTHCompletedRunningPerformance.validFullRecording(
            steps, expectedCount: 5
        ))

        let now = Date()
        var result = WatchWorkoutResult(
            id: UUID(), kind: .running, healthKitWorkoutUUID: nil,
            startedAt: now.addingTimeInterval(-1200), endedAt: now,
            duration: 1200, activeCalories: 100, distanceMeters: 3500,
            averageHeartRate: nil, maxHeartRate: nil, routePointCount: 20
        )
        result.structuredWorkoutFullyCompleted = false
        result.recordedRunningSteps = steps
        XCTAssertNil(ATHLTHCompletedRunningPerformance(watch: result))

        result.structuredWorkoutFullyCompleted = true
        let actual = try XCTUnwrap(
            ATHLTHCompletedRunningPerformance(watch: result)
        )
        XCTAssertEqual(actual.workSteps.count, 2)
        XCTAssertEqual(actual.averageWorkSpeed ?? 0, 12, accuracy: 0.01)
        // Target pace is 4:00/km = 15 km/t; actual was just 12 km/t.
        XCTAssertNotEqual(actual.averageWorkSpeed, 15)
    }
}
