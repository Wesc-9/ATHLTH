import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHRunningKilometerPulseAnalysisTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func split(
        _ kilometer: Int,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval
    ) -> ATHLTHRunningResultInsights.KilometerSplit {
        ATHLTHRunningResultInsights.KilometerSplit(
            kilometer: kilometer,
            durationSeconds: endSeconds - startSeconds,
            startedAt: start.addingTimeInterval(startSeconds),
            endedAt: start.addingTimeInterval(endSeconds)
        )
    }

    private func pulse(
        at seconds: TimeInterval,
        bpm: Double
    ) -> ATHLTHRunningHeartRatePoint {
        ATHLTHRunningHeartRatePoint(
            date: start.addingTimeInterval(seconds),
            bpm: bpm
        )
    }

    private func minute(
        bpm: Double?,
        distance: Double = 200,
        elapsed: Double = 60
    ) -> ATHLTHRecordedRunningMinute {
        ATHLTHRecordedRunningMinute(
            stepIndex: 0,
            stepElapsedAtEndSeconds: elapsed,
            activeSeconds: elapsed,
            recordedDistanceMeters: distance,
            watchHeartRateBPM: bpm,
            targetPaceSecondsPerKilometer: nil,
            targetTreadmillInclinePercent: nil,
            manuallyEnteredTreadmillInclinePercent: nil
        )
    }

    func testGPSKilometresUseOnlyPulseInsideTheirOwnBoundaries() {
        let readings = ATHLTHRunningKilometerPulseAnalysis.results(
            for: [
                split(1, startSeconds: 0, endSeconds: 300),
                split(2, startSeconds: 300, endSeconds: 600)
            ],
            measuredPulse: [
                pulse(at: 35, bpm: 155),
                pulse(at: 140, bpm: 160),
                pulse(at: 345, bpm: 180),
                pulse(at: 500, bpm: 185)
            ],
            recordedMinutes: [],
            athleteMaximumBPM: 200
        )
        XCTAssertEqual(readings[1]?.averageBPM, 158)
        XCTAssertEqual(readings[1]?.observedZone, 3)
        XCTAssertEqual(readings[2]?.averageBPM, 183)
        XCTAssertEqual(readings[2]?.observedZone, 5)
    }

    func testNoPulseNeverUsesWorkoutAverageOrInventsZone() {
        let readings = ATHLTHRunningKilometerPulseAnalysis.results(
            for: [split(1, startSeconds: 0, endSeconds: 300)],
            measuredPulse: [],
            recordedMinutes: [],
            athleteMaximumBPM: 200
        )
        XCTAssertNil(readings[1])
    }

    func testWithoutConfiguredMaximumShowsPulseButNotZone() {
        let readings = ATHLTHRunningKilometerPulseAnalysis.results(
            for: [split(1, startSeconds: 0, endSeconds: 300)],
            measuredPulse: [pulse(at: 150, bpm: 175)],
            recordedMinutes: [],
            athleteMaximumBPM: nil
        )
        XCTAssertEqual(readings[1]?.averageBPM, 175)
        XCTAssertNil(readings[1]?.observedZone)
    }

    func testTreadmillKilometresUseActualWatchMinuteCheckpoints() {
        let minutes = Array(repeating: minute(bpm: 155), count: 5) +
            Array(repeating: minute(bpm: 175), count: 5)
        let splits = ATHLTHRunningResultInsights.kilometerSplits(
            from: minutes, reportedDistanceMeters: 2_000
        )
        let readings = ATHLTHRunningKilometerPulseAnalysis.results(
            for: splits,
            measuredPulse: [],
            recordedMinutes: minutes,
            athleteMaximumBPM: 200
        )
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(readings[1]?.averageBPM, 155)
        XCTAssertEqual(readings[1]?.observedZone, 3)
        XCTAssertEqual(readings[2]?.averageBPM, 175)
        XCTAssertEqual(readings[2]?.observedZone, 4)
    }

    func testSparseOrInvalidWatchPulseIsNotClaimedAsMeasured() {
        let minutes = [minute(bpm: 180)] +
            Array(repeating: minute(bpm: nil), count: 4)
        let splits = ATHLTHRunningResultInsights.kilometerSplits(
            from: minutes, reportedDistanceMeters: 1_000
        )
        XCTAssertEqual(splits.count, 1)
        let result = ATHLTHRunningKilometerPulseAnalysis.results(
            for: splits,
            measuredPulse: [],
            recordedMinutes: minutes,
            athleteMaximumBPM: 200
        )
        XCTAssertNil(result[1])
    }

    func testInvalidGPSPulseIsIgnored() {
        let result = ATHLTHRunningKilometerPulseAnalysis.results(
            for: [split(1, startSeconds: 0, endSeconds: 300)],
            measuredPulse: [pulse(at: 140, bpm: 290)],
            recordedMinutes: [],
            athleteMaximumBPM: 200
        )
        XCTAssertNil(result[1])
    }
}
