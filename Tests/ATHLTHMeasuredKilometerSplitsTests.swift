import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHMeasuredKilometerSplitsTests: XCTestCase {
    private func sample(
        seconds: Double, meters: Double, step: Int = 0
    ) -> ATHLTHRecordedRunningMinute {
        ATHLTHRecordedRunningMinute(
            stepIndex: step,
            stepElapsedAtEndSeconds: seconds,
            activeSeconds: seconds,
            recordedDistanceMeters: meters,
            watchHeartRateBPM: 135,
            targetPaceSecondsPerKilometer: nil,
            targetTreadmillInclinePercent: nil,
            manuallyEnteredTreadmillInclinePercent: nil
        )
    }

    func testWatchTreadmillUsesTwoMeasuredKilometersNotPlannedPace() {
        let minutes = (0..<20).map { i in
            sample(seconds: 47, meters: 100, step: i / 10)
        }
        let splits = ATHLTHRunningResultInsights.kilometerSplits(
            from: minutes, reportedDistanceMeters: 2000
        )
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits.map(\.kilometer), [1, 2])
        XCTAssertEqual(splits[0].durationSeconds, 470, accuracy: 0.01)
        XCTAssertEqual(splits[1].durationSeconds, 470, accuracy: 0.01)
    }

    func testIncompleteKilometerDoesNotInventSplit() {
        let splits = ATHLTHRunningResultInsights.kilometerSplits(
            from: Array(repeating: sample(seconds: 50, meters: 100), count: 7),
            reportedDistanceMeters: 700
        )
        XCTAssertTrue(splits.isEmpty)
    }

    func testReportedDistanceMismatchSuppressesDoubtfulSplit() {
        let samples = Array(repeating: sample(seconds: 50, meters: 100), count: 10)
        XCTAssertTrue(ATHLTHRunningResultInsights.kilometerSplits(
            from: samples, reportedDistanceMeters: 1800
        ).isEmpty)
    }

    func testNoSyntheticSplitsWithoutWatchOrGPSHistory() {
        XCTAssertTrue(ATHLTHRunningResultInsights.kilometerSplits(
            from: [], reportedDistanceMeters: 2100
        ).isEmpty)
    }
}
