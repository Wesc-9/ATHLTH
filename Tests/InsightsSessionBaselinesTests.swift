import Foundation
import HealthKit
import XCTest
@testable import ATHLTH

final class InsightsSessionBaselinesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    private func summary(
        _ activity: HKWorkoutActivityType,
        daysAgo: TimeInterval,
        minutes: TimeInterval
    ) -> WorkoutSummary {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        let duration = minutes * 60
        let workout = HKWorkout(
            activityType: activity,
            start: start,
            end: start.addingTimeInterval(duration),
            duration: duration,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: nil
        )
        return WorkoutSummary(workout: workout)
    }

    func testCalculatesRunningAndAllWorkoutsInOnePass() {
        let workouts = [
            summary(.running, daysAgo: 1, minutes: 30),
            summary(.running, daysAgo: 2, minutes: 60),
            summary(.traditionalStrengthTraining, daysAgo: 3, minutes: 90),
            summary(.running, daysAgo: 40, minutes: 300)
        ]

        let result = InsightsSessionBaselines.calculate(
            workouts: workouts,
            at: now
        )

        XCTAssertEqual(result.allSessionMinutes ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(result.runningSessionMinutes ?? 0, 45, accuracy: 0.001)
    }

    func testEmptyAndOldHistoryDoNotInventWorkoutAverages() {
        let old = summary(.running, daysAgo: 40, minutes: 80)
        let empty = InsightsSessionBaselines.calculate(workouts: [], at: now)
        let expired = InsightsSessionBaselines.calculate(
            workouts: [old], at: now
        )

        XCTAssertNil(empty.allSessionMinutes)
        XCTAssertNil(empty.runningSessionMinutes)
        XCTAssertNil(expired.allSessionMinutes)
        XCTAssertNil(expired.runningSessionMinutes)
    }

    func testNonRunningWorkoutDoesNotBecomeRunningBaseline() {
        let strength = summary(
            .functionalStrengthTraining, daysAgo: 2, minutes: 50
        )

        let result = InsightsSessionBaselines.calculate(
            workouts: [strength],
            at: now
        )

        XCTAssertEqual(result.allSessionMinutes ?? 0, 50, accuracy: 0.001)
        XCTAssertNil(result.runningSessionMinutes)
    }
}
