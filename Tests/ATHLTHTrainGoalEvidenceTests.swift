import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrainGoalEvidenceTests: XCTestCase {
    private func plan() -> TrainingPlan {
        let sessions = (0..<2).map { number in
            PlannedSession(
                id: UUID(), title: "Workout \(number + 1)",
                kind: .strength, scheduledStart: nil,
                durationMinutes: 45,
                targetDistanceKilometers: nil,
                targetPaceSecondsPerKilometer: nil,
                routeID: nil, exercises: [], notes: nil
            )
        }
        return TrainingPlan(
            id: UUID(), ownerID: UUID(), title: "Test plan",
            summary: "", visibility: .privateOnly,
            version: 1,
            weeks: [
                TrainingPlanWeek(
                    id: UUID(), weekNumber: 1, title: "Week 1",
                    days: [
                        TrainingPlanDay(
                            id: UUID(), dayIndex: 1, title: "Monday",
                            sessions: sessions
                        )
                    ]
                )
            ],
            tags: [], createdAt: Date(), updatedAt: Date()
        )
    }

    func testWorkoutGoalCountsOnlyCompletedSessionsOfItsPlan() {
        let plan = plan()
        let goal = ATHLTHGoal(
            title: "Train twice", category: .consistency,
            dataSource: .manual,
            target: GoalTarget(
                metric: .workoutCount,
                targetValue: 2,
                unit: "økter",
                baselineValue: 0,
                activity: nil,
                exerciseName: nil
            ),
            linkedTrainingPlanID: plan.id
        )
        let recorded = plan.weeks[0].days[0].sessions[0].id
        let result = ATHLTHTrainGoalEvidence.evaluate(
            goal: goal, plan: plan,
            strengthHistory: [], completedSessionIDs: [recorded]
        )
        XCTAssertEqual(result.observed, 1)
        XCTAssertEqual(result.target, 2)
        XCTAssertEqual(result.completionFraction, 0.5)
    }

    func testFuturePlannedSessionsAreNotRecordedAsFinished() {
        let plan = plan()
        let goal = ATHLTHGoal(
            title: "Train twice", category: .consistency,
            dataSource: .manual,
            target: GoalTarget(
                metric: .workoutCount, targetValue: 2, unit: "økter",
                baselineValue: 0, activity: nil, exerciseName: nil
            ),
            linkedTrainingPlanID: plan.id
        )
        let result = ATHLTHTrainGoalEvidence.evaluate(
            goal: goal, plan: plan,
            strengthHistory: [], completedSessionIDs: []
        )
        XCTAssertEqual(result.observed, 0)
        XCTAssertEqual(result.completionFraction, 0)
    }

    func testStrengthGoalDoesNotInventWeightFromPlan() {
        let plan = plan()
        let goal = ATHLTHGoal(
            title: "Curl 30 kg", category: .strength,
            dataSource: .athlth,
            target: GoalTarget(
                metric: .strengthWeightKilograms,
                targetValue: 30, unit: "kg", baselineValue: 10,
                activity: nil, exerciseName: "Biceps curl"
            ),
            linkedTrainingPlanID: plan.id
        )
        let result = ATHLTHTrainGoalEvidence.evaluate(
            goal: goal, plan: plan, strengthHistory: [],
            completedSessionIDs: []
        )
        XCTAssertNil(result.observed)
        XCTAssertNil(result.completionFraction)
        XCTAssertFalse(result.hasEvidence)
    }

    func testGoalLinkedToAnotherPlanCannotClaimProgress() {
        let plan = plan()
        let goal = ATHLTHGoal(
            title: "Two workouts", category: .consistency,
            dataSource: .manual,
            target: GoalTarget(
                metric: .workoutCount, targetValue: 2,
                unit: "økter", baselineValue: 0,
                activity: nil, exerciseName: nil
            ),
            linkedTrainingPlanID: UUID()
        )
        let result = ATHLTHTrainGoalEvidence.evaluate(
            goal: goal, plan: plan,
            strengthHistory: [],
            completedSessionIDs: Set(
                plan.weeks.flatMap(\.days).flatMap(\.sessions).map(\.id)
            )
        )
        XCTAssertNil(result.observed)
        XCTAssertNil(result.completionFraction)
    }
}
