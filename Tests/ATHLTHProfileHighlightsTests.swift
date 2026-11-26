import XCTest
@testable import ATHLTH

final class ATHLTHProfileHighlightsTests: XCTestCase {
    func testCompetitionWinPercentageMatchesFinishedContests() {
        let summary = ATHLTHProfileHighlights.CompetitionSnapshot(
            wins: 12, draws: 2, losses: 4, uniqueOpponents: 7
        )
        XCTAssertEqual(summary.finished, 18)
        XCTAssertEqual(summary.winPercent, 66.66666666666667, accuracy: 0.0001)
        XCTAssertEqual(summary.uniqueOpponents, 7)
    }

    func testNoCompletedContestsDoesNotInventWinRateOrRank() {
        let summary = ATHLTHProfileHighlights.CompetitionSnapshot(
            wins: 0, draws: 0, losses: 0, uniqueOpponents: 0
        )
        XCTAssertEqual(summary.winPercent, 0)
        XCTAssertEqual(summary.finished, 0)
    }

    func testMissingRecordedWorkoutsNeverCreatesTopThree() {
        let items = ATHLTHProfileHighlights.mostTrained(
            strength: [], running: [], phone: []
        )
        XCTAssertTrue(items.isEmpty)
    }

    func testMostTrainedFiltersIncludeOnlyAtomicActivities() {
        XCTAssertEqual(
            ATHLTHProfileHighlights.ActivityKind.allCases,
            [.all, .exercise, .interval, .route]
        )
    }
}


final class ATHLTHDigitalTrainingProfileTests: XCTestCase {
    func testRelativeIndexUsesPersonalBaselineAndRejectsMissingEvidence() {
        XCTAssertEqual(ATHLTHDigitalTrainingProfile.relativeIndex(current: 20, baseline: 20), 50)
        XCTAssertEqual(ATHLTHDigitalTrainingProfile.relativeIndex(current: 30, baseline: 20), 75)
        XCTAssertEqual(ATHLTHDigitalTrainingProfile.relativeIndex(current: 100, baseline: 20), 100)
        XCTAssertNil(ATHLTHDigitalTrainingProfile.relativeIndex(current: 20, baseline: 0))
        XCTAssertNil(ATHLTHDigitalTrainingProfile.relativeIndex(current: .infinity, baseline: 20))
    }

    func testEmptyHistoryDoesNotInventAbilityOrRecovery() {
        let snapshot = ATHLTHDigitalTrainingProfile.build(workouts: [], strength: [], recoveryScore: nil)
        XCTAssertEqual(snapshot.metrics.count, 6)
        XCTAssertEqual(snapshot.availableCount, 0)
        let recoveryOnly = ATHLTHDigitalTrainingProfile.build(workouts: [], strength: [], recoveryScore: 84)
        XCTAssertEqual(recoveryOnly.availableCount, 1)
        XCTAssertEqual(recoveryOnly.metrics.first(where: { $0.axis == .recovery })?.score, 84)
    }
}
