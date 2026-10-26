import XCTest
@testable import ATHLTH

final class HomeDailyRecommendationPolicyTests: XCTestCase {
    func testNoWearableDataStillShowsPlanBasedAdvice() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .unavailable, hasWorkoutToday: true,
            trainingLoadRatio: nil
        )
        XCTAssertEqual(advice.destination, .training)
        XCTAssertFalse(advice.title.isEmpty)
        XCTAssertFalse(advice.detail.isEmpty)
    }

    func testNoPlanAndNoHealthDataShowsNeutralSuggestion() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .unavailable, hasWorkoutToday: false,
            trainingLoadRatio: nil
        )
        XCTAssertEqual(advice.destination, .training)
        XCTAssertFalse(advice.source.isEmpty)
    }

    func testRecoveryTakesPriorityOverHighTrainingLoad() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .recover, hasWorkoutToday: true,
            trainingLoadRatio: 1.8
        )
        XCTAssertEqual(advice.destination, .insights)
        XCTAssertEqual(
            advice.source,
            ATHLTHLocalization.choose(
                english: "Based on readiness", norwegian: "Basert på dagsform"
            )
        )
    }

    func testHighTrainingLoadChangesAdviceEvenWhenReady() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready, hasWorkoutToday: true,
            trainingLoadRatio: 1.5
        )
        XCTAssertEqual(advice.destination, .insights)
        XCTAssertEqual(
            advice.source,
            ATHLTHLocalization.choose(
                english: "Based on recent training",
                norwegian: "Basert på treningsbelastning"
            )
        )
    }

    func testNonFiniteLoadIsIgnored() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .unavailable, hasWorkoutToday: true,
            trainingLoadRatio: .nan
        )
        XCTAssertEqual(advice.destination, .training)
    }
}
