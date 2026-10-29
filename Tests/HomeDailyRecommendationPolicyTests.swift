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

    func testHighLoadWithRunningPlanProvidesActionableRunningAdvice() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready,
            hasWorkoutToday: true,
            trainingLoadRatio: 2.86,
            plannedActivity: .running
        )
        XCTAssertEqual(advice.destination, .insights)
        XCTAssertTrue(advice.detail.contains("20"))
        XCTAssertTrue(advice.evidence?.contains("186") == true)
    }

    func testHighLoadWithStrengthPlanSuggestsReducingSets() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .balanced,
            hasWorkoutToday: true,
            trainingLoadRatio: 1.8,
            plannedActivity: .strength
        )
        XCTAssertEqual(advice.destination, .insights)
        XCTAssertTrue(advice.detail.contains("1–2"))
        XCTAssertNotNil(advice.evidence)
    }

    func testLackOfReliableLoadDoesNotInventPercent() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready,
            hasWorkoutToday: true,
            trainingLoadRatio: nil,
            plannedActivity: .running
        )
        XCTAssertNil(advice.evidence)
        XCTAssertEqual(advice.destination, .training)
    }

    func testRecoverWithoutPlanSuggestsLightMovementWithoutWritingPlan() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .recover,
            hasWorkoutToday: false,
            trainingLoadRatio: 1,
            plannedActivity: nil
        )
        XCTAssertTrue(advice.detail.contains("20"))
        XCTAssertEqual(advice.destination, .insights)
    }

    func testNonFiniteLoadIsIgnored() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .unavailable, hasWorkoutToday: true,
            trainingLoadRatio: .nan
        )
        XCTAssertEqual(advice.destination, .training)
    }
    func testReadyWithoutPlanRecommendsRealTimedEasyRun() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready,
            hasWorkoutToday: false,
            trainingLoadRatio: 1
        )
        XCTAssertEqual(advice.suggestedWorkout, .easyRun(minutes: 25))
        XCTAssertFalse(advice.dayDescription.isEmpty)
        XCTAssertFalse(advice.suggestedTitle.isEmpty)
        let workout = HomeDailyRecommendationSessionFactory.make(advice: advice)
        XCTAssertEqual(workout?.kind, .running)
        XCTAssertEqual(workout?.durationMinutes, 25)
        XCTAssertEqual(workout?.resolvedWorkoutBlocks.first?.durationSeconds, 1500)
        XCTAssertEqual(workout?.resolvedWorkoutBlocks.first?.cardioActivity, .running)
    }

    func testUnavailableRecoveryDoesNotClaimGoodCondition() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .unavailable,
            hasWorkoutToday: false,
            trainingLoadRatio: nil
        )
        XCTAssertEqual(advice.suggestedWorkout, .easyWalk(minutes: 20))
        XCTAssertTrue(
            advice.dayDescription.localizedCaseInsensitiveContains(
                ATHLTHLocalization.choose(
                    english: "missing", norwegian: "mangler"
                )
            )
        )
        let workout = HomeDailyRecommendationSessionFactory.make(advice: advice)
        XCTAssertEqual(workout?.kind, .walking)
        XCTAssertEqual(workout?.durationMinutes, 20)
        XCTAssertEqual(workout?.resolvedWorkoutBlocks.first?.durationSeconds, 1200)
        XCTAssertEqual(workout?.resolvedWorkoutBlocks.first?.cardioActivity, .walking)
    }

    func testScheduledWorkoutIsReusedNotDuplicated() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready,
            hasWorkoutToday: true,
            trainingLoadRatio: 0.95,
            plannedActivity: .running,
            plannedWorkoutTitle: "4 x 4 intervaller"
        )
        XCTAssertEqual(advice.suggestedWorkout, .planned)
        XCTAssertEqual(advice.suggestedTitle, "4 x 4 intervaller")
        XCTAssertNil(HomeDailyRecommendationSessionFactory.make(advice: advice))
    }

    func testRecoveryOverridesHardPlanWithoutModifyingIt() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .recover,
            hasWorkoutToday: true,
            trainingLoadRatio: 1.9,
            plannedActivity: .running,
            plannedWorkoutTitle: "Hard intervall"
        )
        XCTAssertEqual(advice.suggestedWorkout, .easyWalk(minutes: 15))
        XCTAssertEqual(
            HomeDailyRecommendationSessionFactory.make(advice: advice)?
                .durationMinutes, 15
        )
        XCTAssertNotEqual(advice.suggestedTitle, "Hard intervall")
    }

    func testHighLoadSuggestsConservativeWalkWhenScheduledStrengthExists() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .balanced,
            hasWorkoutToday: true,
            trainingLoadRatio: 1.7,
            plannedActivity: .strength,
            plannedWorkoutTitle: "Tung styrke"
        )
        XCTAssertEqual(advice.suggestedWorkout, .easyWalk(minutes: 20))
        XCTAssertNotNil(advice.evidence)
    }

}
