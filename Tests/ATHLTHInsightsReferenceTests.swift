import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHInsightsReferenceTests: XCTestCase {
    // Replaced reference-only cards are deliberately removed.
    // Keep regression coverage of the production Health Library instead.
    func testActiveHealthMetricsRetainTrainingGroups() {
        XCTAssertEqual(ATHLTHInsightHealthMetric.allCases.count, 48)
        XCTAssertEqual(ATHLTHInsightHealthArea.allCases.count, 9)
        XCTAssertEqual(ATHLTHInsightHealthMetric.runningPower.area, .fitness)
        XCTAssertEqual(ATHLTHInsightHealthMetric.activeEnergy.area, .activity)
        XCTAssertEqual(ATHLTHInsightHealthMetric.heartRateRecovery.area, .recovery)
    }

    func testTrainingMinutesDoNotMasqueradeAsAClinicalLoadScore() throws {
        let load = RecoveryTrainingLoadSummary(
            acuteMinutes: 300, chronicWeeklyAverageMinutes: 250,
            strengthMinutes: 100, runningMinutes: 160,
            walkingMinutes: 40, otherMinutes: 0
        )
        XCTAssertEqual(try XCTUnwrap(load.ratio), 1.2, accuracy: 0.0001)
        XCTAssertEqual(load.runningMinutes + load.strengthMinutes +
                       load.walkingMinutes + load.otherMinutes, load.acuteMinutes)
    }

    func testThreeInsightsSectionsPreserveUnderlyingHealthMetrics() {
        XCTAssertEqual(ATHLTHInsightsSection.allCases,
                       [.overview, .training, .development])
    }
}
