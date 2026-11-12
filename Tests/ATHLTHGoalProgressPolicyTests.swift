import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHGoalProgressPolicyTests: XCTestCase {
    private func weightGoal() -> ATHLTHGoal {
        ATHLTHGoal(
            title: "Reach 66 kg",
            category: .body,
            dataSource: .appleHealth,
            target: GoalTarget(
                metric: .bodyWeightKilograms,
                targetValue: 66,
                unit: "kg",
                baselineValue: 70
            )
        )
    }

    func testWeightProgressFollowsActualMeasurement() {
        let goal = weightGoal()
        let profile = ATHLTHTrainingProfile()
        XCTAssertEqual(
            ATHLTHGoalProgressPolicy.progress(
                for: goal, profile: profile, latestBodyWeightKilograms: 70
            ), 0
        )
        XCTAssertEqual(
            ATHLTHGoalProgressPolicy.progress(
                for: goal, profile: profile, latestBodyWeightKilograms: 68
            ), 0.5
        )
        XCTAssertEqual(
            ATHLTHGoalProgressPolicy.progress(
                for: goal, profile: profile, latestBodyWeightKilograms: 65
            ), 1
        )
        XCTAssertEqual(
            ATHLTHGoalProgressPolicy.progress(
                for: goal, profile: profile, latestBodyWeightKilograms: 72
            ), 0
        )
    }

    func testWeightProgressFallsBackToMilestonesWhenNoWeightAvailable() {
        let profile = ATHLTHTrainingProfile()
        XCTAssertEqual(
            ATHLTHGoalProgressPolicy.progress(for: weightGoal(), profile: profile),
            0
        )
    }

    func testNewGoalsDefaultToPrivate() {
        XCTAssertEqual(weightGoal().privacy, .privateOnly)
    }
}
