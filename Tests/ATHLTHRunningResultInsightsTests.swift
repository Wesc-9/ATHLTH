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
