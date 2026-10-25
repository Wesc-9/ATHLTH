import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrainOpenDayPolicyTests: XCTestCase {
    private func goal(
        _ category: GoalCategory,
        activity: GoalActivityFilter? = nil,
        status: GoalStatus = .active
    ) -> ATHLTHGoal {
        ATHLTHGoal(
            title: "Test", category: category,
            status: status, dataSource: .manual,
            target: GoalTarget(metric: .manualProgress, targetValue: 1,
                               unit: "", baselineValue: nil,
                               activity: activity, exerciseName: nil)
        )
    }

    func testAlreadyTrainedTakesPriorityOverEncouragingAnotherStart() {
        XCTAssertEqual(
            ATHLTHTrainOpenDayPolicy.choose(
                hasRecordedToday: true, lastCompletedKind: .running,
                activePrimaryGoal: goal(.strength),
                quickTaps: ["running": 10], hasLibrarySuggestion: true
            ), .trainedToday
        )
    }

    func testRepeatCategoryIsBasedOnAnActualCompletedSession() {
        XCTAssertEqual(
            ATHLTHTrainOpenDayPolicy.choose(
                hasRecordedToday: false, lastCompletedKind: .strength,
                activePrimaryGoal: goal(.endurance, activity: .running),
                quickTaps: [:], hasLibrarySuggestion: true
            ), .familiar(.strength)
        )
    }

    func testOnlyExplicitGoalActivityCreatesSpecificEnduranceRecommendation() {
        XCTAssertEqual(
            ATHLTHTrainOpenDayPolicy.choose(
                hasRecordedToday: false, lastCompletedKind: nil,
                activePrimaryGoal: goal(.endurance, activity: .walking),
                quickTaps: [:], hasLibrarySuggestion: false
            ), .goal(.walking)
        )
        XCTAssertEqual(
            ATHLTHTrainOpenDayPolicy.choose(
                hasRecordedToday: false, lastCompletedKind: nil,
                activePrimaryGoal: goal(.endurance),
                quickTaps: [:], hasLibrarySuggestion: true
            ), .library
        )
    }

    func testFavoriteUsesPreviousTapsNotRecordedWorkoutCount() {
        XCTAssertEqual(
            ATHLTHTrainOpenDayPolicy.choose(
                hasRecordedToday: false, lastCompletedKind: nil,
                activePrimaryGoal: nil,
                quickTaps: ["yoga": 3, "running": 1], hasLibrarySuggestion: false
            ), .favorite("yoga")
        )
    }

    func testNoTrainingEvidenceFallsBackToDiscovery() {
        XCTAssertEqual(
            ATHLTHTrainOpenDayPolicy.choose(
                hasRecordedToday: false, lastCompletedKind: nil,
                activePrimaryGoal: nil,
                quickTaps: [:], hasLibrarySuggestion: false
            ), .explore
        )
    }

    func testPausedGoalDoesNotTriggerTrainingSuggestion() {
        XCTAssertEqual(
            ATHLTHTrainOpenDayPolicy.choose(
                hasRecordedToday: false, lastCompletedKind: nil,
                activePrimaryGoal: goal(.strength, status: .paused),
                quickTaps: [:], hasLibrarySuggestion: false
            ), .explore
        )
    }
}
