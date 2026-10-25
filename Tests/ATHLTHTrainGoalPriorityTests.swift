import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrainGoalPriorityTests: XCTestCase {
    private func goal(
        _ title: String,
        category: GoalCategory,
        status: GoalStatus = .active,
        primary: Bool = false,
        activity: GoalActivityFilter? = nil,
        metric: GoalMetric = .manualProgress,
        linkedPlanID: UUID? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 100)
    ) -> ATHLTHGoal {
        ATHLTHGoal(
            title: title, category: category,
            createdAt: createdAt,
            status: status, isPrimary: primary,
            dataSource: .manual,
            target: GoalTarget(
                metric: metric, targetValue: 10, unit: "",
                baselineValue: nil, activity: activity, exerciseName: nil
            ),
            linkedTrainingPlanID: linkedPlanID
        )
    }

    func testOnlySuggestsGoalRelevantToToday'sWorkout() {
        let primary = goal("Regular training", category: .consistency, primary: true)
        let run = goal("Half marathon", category: .endurance)
        let gym = goal("Squat goal", category: .strength)
        XCTAssertEqual(
            ATHLTHTrainGoalPriority.recommend(
                goals: [primary, gym, run], primary: primary,
                activity: .running, activePlanID: nil
            )?.id,
            run.id
        )
        XCTAssertEqual(
            ATHLTHTrainGoalPriority.recommend(
                goals: [primary, gym, run], primary: primary,
                activity: .strength, activePlanID: nil
            )?.id,
            gym.id
        )
        XCTAssertTrue(primary.isPrimary,
            "A display recommendation must never modify the saved primary goal")
    }

    func testActivityFiltersAndUnverifiedEventsDoNotMatch() {
        let walk = goal("Walk 5K", category: .endurance, activity: .walking)
        let race = goal("Upcoming event", category: .event)
        let run = goal("Run 10K", category: .event, activity: .running)
        XCTAssertEqual(
            ATHLTHTrainGoalPriority.recommend(
                goals: [walk, race, run], primary: nil,
                activity: .running, activePlanID: nil
            )?.id,
            run.id
        )
        XCTAssertEqual(
            ATHLTHTrainGoalPriority.recommend(
                goals: [walk, race], primary: nil,
                activity: .walking, activePlanID: nil
            )?.id,
            walk.id
        )
    }

    func testNeverSuggestsPausedFinishedOrOtherPlanGoals() {
        let currentID = UUID(), foreignID = UUID()
        let paused = goal("Paused run", category: .endurance, status: .paused)
        let completed = goal("Done run", category: .endurance, status: .completed)
        let foreign = goal("Other plan", category: .endurance, linkedPlanID: foreignID)
        XCTAssertNil(
            ATHLTHTrainGoalPriority.recommend(
                goals: [paused, completed, foreign], primary: nil,
                activity: .running, activePlanID: currentID
            )
        )
        XCTAssertNil(
            ATHLTHTrainGoalPriority.recommend(
                goals: [foreign], primary: nil,
                activity: .running, activePlanID: nil
            )
        )
    }

    func testNoRecommendationWithoutKnownActivity() {
        let run = goal("Running", category: .endurance)
        let kinds: [WorkoutKind?] = [nil, .custom]
        for kind in kinds {
            XCTAssertNil(ATHLTHTrainGoalPriority.recommend(
                goals: [run], primary: nil, activity: kind, activePlanID: nil
            ))
        }
    }

    func testPlanLinkedRelevantGoalWinsAgainstGeneralOne() {
        let planID = UUID()
        let general = goal("Running", category: .endurance,
            createdAt: Date(timeIntervalSince1970: 200))
        let linked = goal("Linked", category: .endurance,
            linkedPlanID: planID, createdAt: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(
            ATHLTHTrainGoalPriority.recommend(
                goals: [general, linked], primary: nil,
                activity: .running, activePlanID: planID
            )?.id, linked.id
        )
    }
}
