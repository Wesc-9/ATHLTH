import CoreLocation
import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHRunningResultInsightsTests: XCTestCase {
    private func route(count: Int = 24, secondsPerStep: Double = 36) -> [CLLocation] {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return (0..<count).map { index in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 68.0 + Double(index) * 0.0009,
                                                    longitude: 15),
                altitude: Double(index) * 1.5,
                horizontalAccuracy: 6,
                verticalAccuracy: 5,
                course: -1, speed: -1,
                timestamp: start.addingTimeInterval(Double(index) * secondsPerStep)
            )
        }
    }

    func testOnlyCompletedGPSKilometersAreReported() {
        let splits = ATHLTHRunningResultInsights.kilometerSplits(
            from: route(), reportedDistanceMeters: 2_300
        )
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits[0].kilometer, 1)
        XCTAssertEqual(splits[1].kilometer, 2)
        XCTAssertTrue(splits.allSatisfy { $0.durationSeconds > 300 })
    }

    func testVerifiedSplitRetainsTimeRangeForMeasuredPulseMatching() {
        let points = route()
        let splits = ATHLTHRunningResultInsights.kilometerSplits(
            from: points, reportedDistanceMeters: 2_300
        )
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits.first?.startedAt, points.first?.timestamp)
        XCTAssertNotNil(splits.first?.endedAt)
        XCTAssertEqual(splits[1].startedAt, splits[0].endedAt)
        XCTAssertGreaterThan(splits[1].endedAt ?? .distantPast,
                             splits[1].startedAt ?? .distantFuture)
    }

    func testSuspiciousGPSJumpIsNotTurnedIntoBestKilometer() {
        var samples = route()
        samples[8] = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 69.0, longitude: 15),
            altitude: 20, horizontalAccuracy: 5, verticalAccuracy: 5,
            course: -1, speed: -1,
            timestamp: samples[8].timestamp
        )
        XCTAssertTrue(ATHLTHRunningResultInsights.kilometerSplits(
            from: samples, reportedDistanceMeters: 2_300
        ).isEmpty)
    }

    func testMismatchToActualWorkoutSuppressesUnreliableSplits() {
        XCTAssertTrue(ATHLTHRunningResultInsights.kilometerSplits(
            from: route(), reportedDistanceMeters: 10_000
        ).isEmpty)
    }

    func testStrongFinishRequiresTwoCompleteKilometersAndMeasuredGain() {
        typealias Split = ATHLTHRunningResultInsights.KilometerSplit
        XCTAssertNil(ATHLTHRunningResultInsights.strongFinishPercent(
            [Split(kilometer: 1, durationSeconds: 360)]
        ))
        XCTAssertNil(ATHLTHRunningResultInsights.strongFinishPercent(
            [Split(kilometer: 1, durationSeconds: 350),
             Split(kilometer: 2, durationSeconds: 360)]
        ))
        XCTAssertEqual(ATHLTHRunningResultInsights.strongFinishPercent(
            [Split(kilometer: 1, durationSeconds: 400),
             Split(kilometer: 2, durationSeconds: 350)]
        ), 13)
    }

    func testHealthKitDistanceReconstructsAppleStyleKilometerBoundaries() {
        typealias Interval = ATHLTHRunningResultInsights.HealthDistanceInterval
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        var cursor = started
        var intervals: [Interval] = []
        for (duration, count) in [(326.0, 10), (301.0, 10),
                                  (300.0, 10), (193.0, 6)] {
            for _ in 0..<count {
                let next = cursor.addingTimeInterval(duration / Double(count))
                intervals.append(Interval(
                    startDate: cursor, endDate: next, distanceMeters: 100
                ))
                cursor = next
            }
        }
        let splits = ATHLTHRunningResultInsights.healthDistanceKilometerSplits(
            from: intervals,
            workoutStart: started,
            workoutEnd: cursor,
            reportedDistanceMeters: 3_600
        )
        XCTAssertEqual(splits.count, 3, "Partial final kilometre is not a PB")
        XCTAssertEqual(splits.map(\.kilometer), [1, 2, 3])
        XCTAssertEqual(splits[0].durationSeconds, 326, accuracy: 0.01)
        XCTAssertEqual(splits[1].durationSeconds, 301, accuracy: 0.01)
        XCTAssertEqual(splits[2].durationSeconds, 300, accuracy: 0.01)
        XCTAssertEqual(splits[1].startedAt, splits[0].endedAt)
        XCTAssertEqual(splits[2].startedAt, splits[1].endedAt)
    }

    func testHealthKitDistanceRejectsMismatchOrOverlappingSamples() {
        typealias Interval = ATHLTHRunningResultInsights.HealthDistanceInterval
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = (0..<10).map { index in
            Interval(
                startDate: start.addingTimeInterval(Double(index * 30)),
                endDate: start.addingTimeInterval(Double((index + 1) * 30)),
                distanceMeters: 100
            )
        }
        XCTAssertTrue(ATHLTHRunningResultInsights.healthDistanceKilometerSplits(
            from: samples, workoutStart: start,
            workoutEnd: start.addingTimeInterval(300),
            reportedDistanceMeters: 1_400
        ).isEmpty)
        XCTAssertTrue(ATHLTHRunningResultInsights.healthDistanceKilometerSplits(
            from: samples + [samples[4]], workoutStart: start,
            workoutEnd: start.addingTimeInterval(300),
            reportedDistanceMeters: 1_100
        ).isEmpty)
    }

    func testHealthKitDistanceExcludesConfirmedWorkoutPause() {
        typealias Interval = ATHLTHRunningResultInsights.HealthDistanceInterval
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = (0..<10).map { index -> Interval in
            let pauseOffset = index >= 5 ? 40.0 : 0
            let begin = start.addingTimeInterval(
                Double(index * 30) + pauseOffset
            )
            return Interval(
                startDate: begin,
                endDate: begin.addingTimeInterval(30),
                distanceMeters: 100
            )
        }
        let splits = ATHLTHRunningResultInsights.healthDistanceKilometerSplits(
            from: samples, workoutStart: start,
            workoutEnd: start.addingTimeInterval(340),
            reportedDistanceMeters: 1_000,
            pausedIntervals: [
                DateInterval(
                    start: start.addingTimeInterval(150),
                    end: start.addingTimeInterval(190)
                )
            ]
        )
        XCTAssertEqual(splits.count, 1)
        XCTAssertEqual(splits[0].durationSeconds, 300, accuracy: 0.01)
        XCTAssertEqual(splits[0].endedAt, start.addingTimeInterval(340))
    }

    func testHealthKitDistanceRejectsCoalescedLowResolutionData() {
        typealias Interval = ATHLTHRunningResultInsights.HealthDistanceInterval
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = (0..<3).map { index in
            Interval(
                startDate: start.addingTimeInterval(Double(index * 250)),
                endDate: start.addingTimeInterval(Double((index + 1) * 250)),
                distanceMeters: 350
            )
        }
        XCTAssertTrue(ATHLTHRunningResultInsights.healthDistanceKilometerSplits(
            from: samples, workoutStart: start,
            workoutEnd: start.addingTimeInterval(750),
            reportedDistanceMeters: 1_050
        ).isEmpty)
    }

    func testElevationRequiresQualifiedSamples() {
        let valid = ATHLTHRunningResultInsights.elevationProfile(from: route())
        XCTAssertGreaterThan(valid.count, 4)
        XCTAssertGreaterThan(valid.last?.distanceKilometers ?? 0, 1.8)
        var invalid = route()
        invalid[7] = CLLocation(
            coordinate: invalid[7].coordinate, altitude: 200,
            horizontalAccuracy: 5, verticalAccuracy: 5,
            course: -1, speed: -1,
            timestamp: invalid[7].timestamp
        )
        XCTAssertTrue(ATHLTHRunningResultInsights.elevationProfile(from: invalid).isEmpty)
    }

    func testMissingRouteDoesNotFabricateInsights() {
        // Both CLLocation and ATHLTHRecordedRunningMinute overloads exist.
        // Explicitly use a missing GPS route for this regression test.
        let emptyGPSRoute: [CLLocation] = []
        XCTAssertTrue(ATHLTHRunningResultInsights.kilometerSplits(
            from: emptyGPSRoute, reportedDistanceMeters: 5_000
        ).isEmpty)
        XCTAssertNil(ATHLTHRunningResultInsights.bestKilometer([]))
        XCTAssertTrue(ATHLTHRunningResultInsights.elevationProfile(from: []).isEmpty)
    }
}
