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
