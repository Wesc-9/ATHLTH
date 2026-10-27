import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHInsightsReferenceTests: XCTestCase {
    func testSleepTrendConvertsSecondsToHours() {
        let sample = RecoveryTrendDay(
            date: Date(), sleepDuration: 7 * 3600 + 30 * 60,
            hrvMilliseconds: 68, restingHeartRate: 52,
            respiratoryRate: 13.6, trainingMinutes: 40
        )
        XCTAssertEqual(ATHLTHInsightReferenceMetric.sleep.value(sample), 7.5)
        XCTAssertEqual(ATHLTHInsightReferenceMetric.sleep.label(7.5), "7 t 30 min")
        XCTAssertEqual(ATHLTHInsightReferenceMetric.hrv.value(sample), 68)
        XCTAssertEqual(ATHLTHInsightReferenceMetric.restingHeartRate.value(sample), 52)
        XCTAssertEqual(ATHLTHInsightReferenceMetric.respiratory.value(sample), 13.6)
    }

    func testMissingHealthSignalsStayMissing() {
        let missing = RecoveryTrendDay(
            date: Date(), sleepDuration: nil,
            hrvMilliseconds: nil, restingHeartRate: nil,
            respiratoryRate: nil, trainingMinutes: 0
        )
        XCTAssertNil(ATHLTHInsightReferenceMetric.sleep.value(missing))
        XCTAssertNil(ATHLTHInsightReferenceMetric.hrv.value(missing))
        XCTAssertNil(ATHLTHInsightReferenceMetric.restingHeartRate.value(missing))
        XCTAssertNil(ATHLTHInsightReferenceMetric.respiratory.value(missing))
    }

    func testTrainingMinutesDoNotMasqueradeAsAClinicalLoadScore() {
        let load = RecoveryTrainingLoadSummary(
            acuteMinutes: 300, chronicWeeklyAverageMinutes: 250,
            strengthMinutes: 100, runningMinutes: 160,
            walkingMinutes: 40, otherMinutes: 0
        )
        XCTAssertEqual(load.ratio, 1.2, accuracy: 0.0001)
        XCTAssertEqual(load.runningMinutes + load.strengthMinutes +
                       load.walkingMinutes + load.otherMinutes, load.acuteMinutes)
    }

    func testFourReferenceSectionsAreAvailable() {
        XCTAssertEqual(ATHLTHInsightsSection.allCases,
                       [.overview, .health, .training, .development])
        XCTAssertEqual(ATHLTHInsightReferenceMetric.allCases.count, 4)
    }
}
