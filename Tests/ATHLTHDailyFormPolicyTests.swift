import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHDailyFormPolicyTests: XCTestCase {
    private func entry(energy: Int? = nil, stress: Int? = nil, motivation: Int? = nil,
                       sleep: Int? = nil, unwell: Bool? = nil) -> RecoverySorenessEntry {
        RecoverySorenessEntry(date: Calendar.current.startOfDay(for: Date()), ratings: [:],
            energy: energy, stress: stress, overallSoreness: nil,
            motivation: motivation, sleepQuality: sleep, feelsUnwell: unwell)
    }

    func testMissingAnswersDoNotInventAScore() {
        let result = ATHLTHDailyFormPolicy.assess(entry: nil, measuredScore: nil)
        XCTAssertNil(result.subjectiveScore)
        XCTAssertNil(result.contextualScore)
        XCTAssertEqual(result.recommendation, .unavailable)
    }

    func testLowEnergyOverridesGoodMeasuredReadinessWithoutChangingIt() {
        let result = ATHLTHDailyFormPolicy.assess(entry: entry(energy: 1), measuredScore: 90)
        XCTAssertEqual(result.measuredScore, 90)
        XCTAssertNil(result.contextualScore)
        XCTAssertEqual(result.recommendation, .lighter)
        XCTAssertEqual(ATHLTHDailyFormPolicy.recommendationReadiness(.ready, entry: entry(energy: 1)), .takeItEasy)
    }

    func testSubjectiveScoreCannotRaiseLowMeasuredReadiness() {
        let result = ATHLTHDailyFormPolicy.assess(entry: entry(energy: 5, stress: 1, motivation: 5, sleep: 5), measuredScore: 40)
        XCTAssertEqual(result.subjectiveScore, 100)
        XCTAssertEqual(result.contextualScore, 40)
        XCTAssertEqual(result.recommendation, .lighter)
    }

    func testIllnessRecommendsRestRatherThanWalking() {
        let assessment = ATHLTHDailyFormPolicy.assess(entry: entry(energy: 5, unwell: true), measuredScore: 95)
        XCTAssertEqual(assessment.recommendation, .rest)
        let advice = HomeDailyRecommendationPolicy.recommendation(readiness: .ready,
            hasWorkoutToday: false, trainingLoadRatio: nil, checkIn: assessment)
        XCTAssertEqual(advice.suggestedWorkout, .restDay)
    }

    func testAccountScopedCheckInsDoNotLeakOrOverwrite() {
        let defaults = UserDefaults(suiteName: "athlth.dailyform.tests.\(UUID())")!
        let first = UUID(), second = UUID()
        let a = RecoverySorenessStore(defaults: defaults, accountID: first)
        var draft = RecoveryPartialCheckInDraft()
        draft.energy = 2
        draft.sleepQuality = 3
        draft.feelsUnwell = false
        a.applyCheckIn(draft)
        XCTAssertFalse(RecoverySorenessStore(defaults: defaults, accountID: second).hasTodayCheckIn)
        let restored = RecoverySorenessStore(defaults: defaults, accountID: first)
        XCTAssertEqual(restored.todayEnergy, 2)
        XCTAssertEqual(restored.todayEntry?.sleepQuality, 3)
        XCTAssertEqual(restored.todayEntry?.feelsUnwell, false)
    }

    func testFeedbackIsPrivateAndMergesPartialAnswers() {
        let defaults = UserDefaults(suiteName: "athlth.workoutfeedback.tests.\(UUID())")!
        let account = UUID(), workout = UUID(), date = Date()
        XCTAssertTrue(ATHLTHPostWorkoutFeedbackStore.save(.init(workoutID: workout, finishedAt: date, feeling: 4, exertion: nil), account: account, defaults: defaults))
        XCTAssertTrue(ATHLTHPostWorkoutFeedbackStore.save(.init(workoutID: workout, finishedAt: date, feeling: nil, exertion: 8), account: account, defaults: defaults))
        let stored = ATHLTHPostWorkoutFeedbackStore.entries(account: account, defaults: defaults)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.feeling, 4)
        XCTAssertEqual(stored.first?.exertion, 8)
        XCTAssertTrue(ATHLTHPostWorkoutFeedbackStore.entries(account: UUID(), defaults: defaults).isEmpty)
    }
}
