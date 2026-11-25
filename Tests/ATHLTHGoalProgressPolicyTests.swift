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

    func testAchievementRetainsProgressAfterMeasurementChangesAndArchive() {
        var goal = weightGoal()
        goal.status = .completed
        goal.completedAt = Date()
        XCTAssertTrue(goal.isAchievement)
        XCTAssertEqual(ATHLTHGoalProgressPolicy.progress(for: goal, profile: ATHLTHTrainingProfile(), latestBodyWeightKilograms: 80), 1)
        goal.status = .abandoned
        XCTAssertTrue(goal.isAchievement)
        XCTAssertEqual(goal.progress, 1)
        goal.completedAt = nil
        XCTAssertFalse(goal.isAchievement)
    }

    func testNewGoalsDefaultToPrivate() {
        XCTAssertEqual(weightGoal().privacy, .privateOnly)
    }
}
