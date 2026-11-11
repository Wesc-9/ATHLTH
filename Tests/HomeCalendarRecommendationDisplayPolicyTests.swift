import XCTest
@testable import ATHLTH

final class HomeCalendarRecommendationDisplayPolicyTests: XCTestCase {
    func testRecommendationShowsOnlyWhenCalendarHasAtMostOneActivity() {
        XCTAssertTrue(HomeCalendarRecommendationDisplayPolicy.showsRecommendation(
            plannedWorkoutCount: 0,
            personalEventCount: 0,
            clubEventCount: 0,
            tournamentCount: 0
        ))
        XCTAssertTrue(HomeCalendarRecommendationDisplayPolicy.showsRecommendation(
            plannedWorkoutCount: 1,
            personalEventCount: 0,
            clubEventCount: 0,
            tournamentCount: 0
        ))
        XCTAssertFalse(HomeCalendarRecommendationDisplayPolicy.showsRecommendation(
            plannedWorkoutCount: 2,
            personalEventCount: 0,
            clubEventCount: 0,
            tournamentCount: 0
        ))
    }

    func testDifferentCalendarSourcesAlsoHideRecommendationWhenCombined() {
        XCTAssertFalse(HomeCalendarRecommendationDisplayPolicy.showsRecommendation(
            plannedWorkoutCount: 1,
            personalEventCount: 0,
            clubEventCount: 1,
            tournamentCount: 0
        ))
        XCTAssertFalse(HomeCalendarRecommendationDisplayPolicy.showsRecommendation(
            plannedWorkoutCount: 0,
            personalEventCount: 1,
            clubEventCount: 0,
            tournamentCount: 1
        ))
    }
}
