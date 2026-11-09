import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHStudioRecordedWorkoutsTests: XCTestCase {
    private func strength(
        id: UUID = UUID(),
        healthID: UUID? = nil,
        started: Date = .now,
        finished: Bool = true
    ) -> StrengthWorkoutLog {
        StrengthWorkoutLog(
            id: id,
            plannedSessionID: nil,
            watchSessionID: nil,
            captureDevice: .iPhone,
            trackingMode: .simple,
            title: "Strength",
            startedAt: started,
            endedAt: finished ? started.addingTimeInterval(2_400) : nil,
            exercises: [],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: healthID,
                duration: finished ? 2_400 : nil,
                activeCalories: nil,
                averageHeartRate: nil,
                maxHeartRate: nil
            )
        )
    }

    func testLocallyCompletedStrengthWorkoutAppearsWithoutAppleHealth() {
        let local = strength()
        let result = ATHLTHStudioRecordedWorkouts.merged(
            health: [], localStrength: [local]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, local.id)
        XCTAssertEqual(result.first?.activity, .strength)
        XCTAssertEqual(result.first?.duration, 2_400)
    }

    func testLinkedWorkoutIsNotDoubleCounted() {
        let healthID = UUID()
        let local = strength(healthID: healthID)
        let healthSummary = WorkoutSummary(localStrengthWorkout: local)
        let result = ATHLTHStudioRecordedWorkouts.merged(
            health: [healthSummary], localStrength: [local]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, healthID)
    }

    func testMatchingHealthTimesAreNotDoubleCountedWhenLinkMissing() {
        let moment = Date.now
        let local = strength(started: moment)
        let healthLike = WorkoutSummary(
            localStrengthWorkout: strength(started: moment)
        )
        let result = ATHLTHStudioRecordedWorkouts.merged(
            health: [healthLike], localStrength: [local]
        )
        XCTAssertEqual(result.count, 1)
    }

    func testUnfinishedLocalStrengthIsNotCountedAsRecorded() {
        let active = strength(finished: false)
        let result = ATHLTHStudioRecordedWorkouts.merged(
            health: [], localStrength: [active]
        )
        XCTAssertTrue(result.isEmpty)
    }
}
