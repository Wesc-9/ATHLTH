import SwiftUI
import XCTest
@testable import ATHLTH

final class HomeDailyRecommendationPolicyTests: XCTestCase {
    @MainActor
    func testCompactRecommendationKeepsSameHeightForShortAndLongAdvice() {
        XCTAssertEqual(HomeTodayTwinCardLayout.height, 174)
        let adviceSamples: [HomeDailyRecommendationPolicy.Advice] = [
            HomeDailyRecommendationPolicy.recommendation(
                readiness: .ready,
                hasWorkoutToday: false,
                trainingLoadRatio: nil
            ),
            HomeDailyRecommendationPolicy.recommendation(
                readiness: .unavailable,
                hasWorkoutToday: true,
                trainingLoadRatio: nil
            ),
            HomeDailyRecommendationPolicy.recommendation(
                readiness: .balanced,
                hasWorkoutToday: true,
                trainingLoadRatio: 1.85,
                plannedActivity: .running
            )
        ]

        for width in [158.0, 185.0, 225.0] {
            for advice in adviceSamples {
                let card = HomeDailyRecommendationCard(
                    advice: advice,
                    onStartRecommendedWorkout: {},
                    compact: true
                )
                .frame(width: width)

                let host = UIHostingController(rootView: card)
                host.loadViewIfNeeded()
                let measured = host.sizeThatFits(in: CGSize(width: width, height: 400))
                XCTAssertEqual(
                    measured.height,
                    HomeTodayTwinCardLayout.height,
                    accuracy: 1,
                    "Recommendation must match the calendar card height"
                )
                XCTAssertLessThanOrEqual(measured.width, width + 1)
            }
        }
    }

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
    func testReadyWithoutRunHistoryDoesNotAssumeRunningExperience() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready,
            hasWorkoutToday: false,
            trainingLoadRatio: 1
        )
        XCTAssertEqual(advice.suggestedWorkout, .easyWalk(minutes: 20))
        XCTAssertTrue(advice.dayDescription.localizedCaseInsensitiveContains(
            ATHLTHLocalization.choose(
                english: "last 28 days", norwegian: "28 dagene"
            )
        ))
        let workout = HomeDailyRecommendationSessionFactory.make(advice: advice)
        XCTAssertEqual(workout?.kind, .walking)
        XCTAssertEqual(workout?.durationMinutes, 20)
        XCTAssertEqual(workout?.resolvedWorkoutBlocks.first?.durationSeconds, 1200)
        XCTAssertEqual(workout?.resolvedWorkoutBlocks.first?.cardioActivity, .walking)
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


    private func trainingHistory(
        runs: Int,
        lastRunDaysAgo: Int?,
        averageMinutes: Int?
    ) -> HomeDailyRecommendationPolicy.TrainingHistory {
        .init(
            sessionsLast28Days: runs,
            runsLast28Days: runs,
            mostRecentRunDaysAgo: lastRunDaysAgo,
            averageRecentRunMinutes: averageMinutes
        )
    }

    func testReadyWithRepeatedRecentRunsSuggestsControlledTempo() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready,
            hasWorkoutToday: false,
            trainingLoadRatio: 0.58,
            trainingHistory: trainingHistory(
                runs: 4, lastRunDaysAgo: 2, averageMinutes: 36
            )
        )
        XCTAssertEqual(advice.suggestedWorkout, .tempoRun(minutes: 35))
        XCTAssertTrue(advice.dayDescription.localizedCaseInsensitiveContains(
            ATHLTHLocalization.choose(
                english: "tempo", norwegian: "tempoøkt"
            )
        ))
        let workout = HomeDailyRecommendationSessionFactory.make(advice: advice)
        XCTAssertEqual(workout?.kind, .running)
        XCTAssertEqual(workout?.durationMinutes, 35)
        XCTAssertEqual(workout?.resolvedWorkoutBlocks.count, 7)
        XCTAssertEqual(
            workout?.resolvedWorkoutBlocks
                .compactMap(\.durationSeconds).reduce(0, +),
            2_100
        )
        XCTAssertEqual(workout?.resolvedWorkoutBlocks.first?.resolvedPhase, .warmup)
        XCTAssertEqual(workout?.resolvedWorkoutBlocks.last?.resolvedPhase, .cooldown)
        XCTAssertEqual(workout?.resolvedWorkoutBlocks[1].targetEffortRPE, 6)
    }

    func testReadyWithSomeRecentRunningSuggestsGradualProgression() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready,
            hasWorkoutToday: false,
            trainingLoadRatio: 0.35,
            trainingHistory: trainingHistory(
                runs: 1, lastRunDaysAgo: 2, averageMinutes: 28
            )
        )
        XCTAssertEqual(advice.suggestedWorkout, .progressiveRun(minutes: 30))
        let workout = HomeDailyRecommendationSessionFactory.make(advice: advice)
        XCTAssertEqual(workout?.resolvedWorkoutBlocks.count, 3)
        XCTAssertEqual(
            workout?.resolvedWorkoutBlocks
                .compactMap(\.durationSeconds).reduce(0, +),
            1_800
        )
        XCTAssertEqual(workout?.resolvedWorkoutBlocks[1].targetEffortRPE, 5)
    }

    func testReadyWithStaleRunningHistoryDoesNotEscalate() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready,
            hasWorkoutToday: false,
            trainingLoadRatio: 0.1,
            trainingHistory: trainingHistory(
                runs: 5, lastRunDaysAgo: 21, averageMinutes: 45
            )
        )
        XCTAssertEqual(advice.suggestedWorkout, .easyWalk(minutes: 20))
        XCTAssertTrue(advice.dayDescription.contains("21"))
    }

    func testBalancedReadinessCanRecommendSteadyProgression() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .balanced,
            hasWorkoutToday: false,
            trainingLoadRatio: 0.8,
            trainingHistory: trainingHistory(
                runs: 2, lastRunDaysAgo: 2, averageMinutes: 34
            )
        )
        XCTAssertEqual(advice.suggestedWorkout, .progressiveRun(minutes: 30))
    }

    func testSeveralDaysWithoutRunningDoesNotRecommendProgression() {
        for days in [3, 4, 6, 10, 14] {
            for readiness in [
                HomeDailyRecommendationPolicy.Readiness.balanced, .ready
            ] {
                let advice = HomeDailyRecommendationPolicy.recommendation(
                    readiness: readiness,
                    hasWorkoutToday: false,
                    trainingLoadRatio: 0.8,
                    trainingHistory: trainingHistory(
                        runs: 3, lastRunDaysAgo: days, averageMinutes: 32
                    )
                )
                XCTAssertEqual(advice.suggestedWorkout, .easyRun(minutes: 20))
                XCTAssertTrue(advice.dayDescription.contains("\(days)"),
                              "Description must state actual days since recorded run")
                XCTAssertFalse(advice.dayDescription.localizedCaseInsensitiveContains(
                    ATHLTHLocalization.choose(
                        english: "recent runs", norwegian: "løpt nylig"
                    )
                ))
            }
        }
    }

    func testLongGapOrUnavailableRunHistoryNeverClaimsRecentRunning() {
        for days in [15, 21, 28] {
            let advice = HomeDailyRecommendationPolicy.recommendation(
                readiness: .balanced,
                hasWorkoutToday: false,
                trainingLoadRatio: nil,
                trainingHistory: trainingHistory(
                    runs: 3, lastRunDaysAgo: days, averageMinutes: 40
                )
            )
            XCTAssertEqual(advice.suggestedWorkout, .easyWalk(minutes: 20))
            XCTAssertTrue(advice.dayDescription.contains("\(days)"))
        }
        let missing = HomeDailyRecommendationPolicy.recommendation(
            readiness: .balanced,
            hasWorkoutToday: false,
            trainingLoadRatio: nil,
            trainingHistory: .empty
        )
        XCTAssertEqual(missing.suggestedWorkout, .easyWalk(minutes: 20))
        XCTAssertFalse(missing.dayDescription.localizedCaseInsensitiveContains(
            ATHLTHLocalization.choose(
                english: "recent runs", norwegian: "løpt nylig"
            )
        ))
    }

    func testMultipleOldRunsDoNotAllowHardTempoBecauseReadinessIsGood() {
        for days in [3, 6, 10] {
            let advice = HomeDailyRecommendationPolicy.recommendation(
                readiness: .ready,
                hasWorkoutToday: false,
                trainingLoadRatio: 0.5,
                trainingHistory: trainingHistory(
                    runs: 8, lastRunDaysAgo: days, averageMinutes: 45
                )
            )
            XCTAssertEqual(advice.suggestedWorkout, .easyRun(minutes: 20))
        }
    }

    func testPoorReadinessAndExcessiveLoadOverrideRunningHistory() {
        let prior = trainingHistory(
            runs: 6, lastRunDaysAgo: 1, averageMinutes: 45
        )
        for readiness in [
            HomeDailyRecommendationPolicy.Readiness.recover,
            .takeItEasy
        ] {
            let advice = HomeDailyRecommendationPolicy.recommendation(
                readiness: readiness,
                hasWorkoutToday: false,
                trainingLoadRatio: 0.7,
                trainingHistory: prior
            )
            if case .easyWalk = advice.suggestedWorkout {
                // Keep active recovery only.
            } else {
                XCTFail("Poor readiness must not suggest a tempo run.")
            }
        }
        let over = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready,
            hasWorkoutToday: false,
            trainingLoadRatio: 1.7,
            trainingHistory: prior
        )
        XCTAssertEqual(over.suggestedWorkout, .easyWalk(minutes: 20))
    }

    func testExistingPlannedWorkoutKeepsPriorityWhenHealthy() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready,
            hasWorkoutToday: true,
            trainingLoadRatio: 0.5,
            plannedActivity: .strength,
            plannedWorkoutTitle: "Min egen styrkeøkt",
            trainingHistory: trainingHistory(
                runs: 5, lastRunDaysAgo: 1, averageMinutes: 40
            )
        )
        XCTAssertEqual(advice.suggestedWorkout, .planned)
        XCTAssertNil(HomeDailyRecommendationSessionFactory.make(advice: advice))
    }


    func testAlreadyCompletedWorkoutAvoidsSecondDemandingSession() {
        var history = trainingHistory(
            runs: 4, lastRunDaysAgo: 0, averageMinutes: 38
        )
        history.hasCompletedWorkoutToday = true
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready,
            hasWorkoutToday: false,
            trainingLoadRatio: 0.6,
            trainingHistory: history
        )
        XCTAssertEqual(advice.suggestedWorkout, .easyWalk(minutes: 20))
        XCTAssertTrue(advice.dayDescription.localizedCaseInsensitiveContains(
            ATHLTHLocalization.choose(
                english: "already completed", norwegian: "allerede trent"
            )
        ))
    }

    func testTempoRequiresAtLeastOneRecoveryDaySinceLastRun() {
        let advice = HomeDailyRecommendationPolicy.recommendation(
            readiness: .ready,
            hasWorkoutToday: false,
            trainingLoadRatio: 0.8,
            trainingHistory: trainingHistory(
                runs: 4, lastRunDaysAgo: 1, averageMinutes: 40
            )
        )
        XCTAssertEqual(advice.suggestedWorkout, .progressiveRun(minutes: 30))
    }

}
