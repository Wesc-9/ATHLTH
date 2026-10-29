import XCTest
@testable import ATHLTH

final class ATHLTHInsightsWhatIfComparisonTests: XCTestCase {
    func testAddingOneWorkoutDoesNotReplaceTheExistingWeek() {
        let comparison = ATHLTHInsightsWhatIfComparison(
            historicalWeeklyMinutes: 120,
            historicalWeeklySessions: 3,
            additionalMinutes: 45
        )
        XCTAssertEqual(comparison.projectedWeeklyMinutes, 165)
        XCTAssertEqual(comparison.projectedWeeklySessions, 4)
        XCTAssertEqual(comparison.increasePercent ?? 0, 37.5, accuracy: 0.001)
    }

    func testMissingTrainingHistoryStaysUnknown() {
        let comparison = ATHLTHInsightsWhatIfComparison(
            historicalWeeklyMinutes: nil,
            historicalWeeklySessions: nil,
            additionalMinutes: 30
        )
        XCTAssertNil(comparison.projectedWeeklyMinutes)
        XCTAssertNil(comparison.projectedWeeklySessions)
        XCTAssertNil(comparison.increasePercent)
    }

    func testZeroHistoricalMinutesDoesNotInventPercentIncrease() {
        let comparison = ATHLTHInsightsWhatIfComparison(
            historicalWeeklyMinutes: 0,
            historicalWeeklySessions: 0,
            additionalMinutes: 30
        )
        XCTAssertEqual(comparison.projectedWeeklyMinutes, 30)
        XCTAssertNil(comparison.increasePercent)
    }

    func testAPlannedWorkoutCannotSubtractMinutes() {
        let comparison = ATHLTHInsightsWhatIfComparison(
            historicalWeeklyMinutes: 100,
            historicalWeeklySessions: 2,
            additionalMinutes: -5
        )
        XCTAssertEqual(comparison.projectedWeeklyMinutes, 100)
    }
}
