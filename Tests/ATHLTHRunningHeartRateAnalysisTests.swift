import CoreLocation
import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHRunningHeartRateAnalysisTests: XCTestCase {
    private let started = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(_ seconds: TimeInterval, bpm: Double)
        -> ATHLTHRunningHeartRatePoint {
        ATHLTHRunningHeartRatePoint(
            date: started.addingTimeInterval(seconds), bpm: bpm
        )
    }

    func testTimeInZonesUsesActualMeasurementsOnly() {
        let points = [
            sample(0, bpm: 110),
            sample(30, bpm: 135),
            sample(60, bpm: 150),
            sample(90, bpm: 175)
        ]
        let durations = ATHLTHRunningHeartRateAnalysis.zoneDurations(
            points, maximumBPM: 200
        )
        XCTAssertEqual(durations.count, 5)
        XCTAssertEqual(durations[0].seconds, 30, accuracy: 0.1)
        XCTAssertEqual(durations[1].seconds, 30, accuracy: 0.1)
        XCTAssertEqual(durations[2].seconds, 30, accuracy: 0.1)
        XCTAssertEqual(durations.reduce(0) { $0 + $1.seconds }, 90, accuracy: 0.1)
    }

    func testMissingSensorPeriodsAreNotInvented() {
        let data = [sample(0, bpm: 145), sample(240, bpm: 155),
                    sample(270, bpm: 155)]
        let durations = ATHLTHRunningHeartRateAnalysis.zoneDurations(
            data, maximumBPM: 200
        )
        XCTAssertEqual(durations.reduce(0) { $0 + $1.seconds }, 30, accuracy: 0.1)
    }

    func testNoMaximumHeartRateMeansNoZoneClaim() {
        let data = [sample(0, bpm: 150), sample(30, bpm: 155)]
        let durations = ATHLTHRunningHeartRateAnalysis.zoneDurations(
            data, maximumBPM: nil
        )
        XCTAssertEqual(durations.reduce(0) { $0 + $1.seconds }, 0)
    }

    func testPulseAverageUsesOnlySamplesInsideVerifiedSplit() {
        let points = [sample(0, bpm: 110), sample(40, bpm: 130),
                      sample(70, bpm: 150), sample(130, bpm: 160)]
        let avg = ATHLTHRunningHeartRateAnalysis.average(
            points,
            from: started.addingTimeInterval(30),
            through: started.addingTimeInterval(100)
        )
        XCTAssertEqual(avg ?? 0, 140, accuracy: 0.01)
    }

    func testInvalidSamplesAreExcludedAndChartRemainsBounded() {
        let values = (0..<500).map { sample(Double($0), bpm: $0 == 6 ? 550 : 140) }
        let verified = ATHLTHRunningHeartRateAnalysis.validPoints(
            values, from: started, through: started.addingTimeInterval(500)
        )
        XCTAssertEqual(verified.count, 499)
        let reduced = ATHLTHRunningHeartRateAnalysis.chartPoints(verified)
        XCTAssertLessThanOrEqual(reduced.count, 280)
        XCTAssertEqual(reduced.first?.date, verified.first?.date)
        XCTAssertEqual(reduced.last?.date, verified.last?.date)
    }

    func testVerifiedFourByFourMapsPulseOnlyToItsOwnEffort() {
        let steps = [
            ATHLTHRecordedRunningStep(index: 0, title: "Oppvarming",
                phase: "warmup", activeSeconds: 600, distanceMeters: 800),
            ATHLTHRecordedRunningStep(index: 1, title: "Drag 1",
                phase: "work", activeSeconds: 240, distanceMeters: 700),
            ATHLTHRecordedRunningStep(index: 2, title: "Pause",
                phase: "recovery", activeSeconds: 120, distanceMeters: 150)
        ]
        let pulse = [sample(30, bpm: 105), sample(610, bpm: 145),
                     sample(720, bpm: 172), sample(860, bpm: 110)]
        let work = ATHLTHRunningHeartRateAnalysis.phasePoints(
            pulse, phaseIndex: 1, steps: steps, startedAt: started,
            endedAt: started.addingTimeInterval(960)
        )
        XCTAssertEqual(work.map(\.bpm), [145, 172])

        let pausedSession = ATHLTHRunningHeartRateAnalysis.phasePoints(
            pulse, phaseIndex: 1, steps: steps, startedAt: started,
            endedAt: started.addingTimeInterval(1_200)
        )
        XCTAssertTrue(pausedSession.isEmpty)
    }
}
