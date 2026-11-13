import XCTest
@testable import ATHLTH

final class ATHLTHReplayDataQualityTests: XCTestCase {
    func testAccidentalOvernightRunIsFlaggedAndPaceSuppressed() {
        // The regression shown in the UI: ~6h45 for just 20 metres.
        let duration: TimeInterval = 6 * 3600 + 45 * 60
        XCTAssertTrue(ATHLTHReplayDataQuality.needsReview(
            activity: .running,
            isIndoor: false,
            duration: duration,
            distanceMeters: 20
        ))
        XCTAssertNil(ATHLTHReplayDataQuality.usablePace(
            duration: duration,
            distanceMeters: 20,
            activity: .running,
            requiresReview: true
        ))
        XCTAssertFalse(ATHLTHReplayDataQuality.reliableSegment(
            distanceMeters: 5,
            paceSecondsPerKilometer: 9_000,
            activity: .running
        ))
    }

    func testNormalOutdoorRunRetainsValidInsights() {
        XCTAssertFalse(ATHLTHReplayDataQuality.needsReview(
            activity: .running,
            isIndoor: false,
            duration: 31 * 60,
            distanceMeters: 5_000
        ))
        XCTAssertEqual(
            ATHLTHReplayDataQuality.usablePace(
                duration: 31 * 60,
                distanceMeters: 5_000,
                activity: .running,
                requiresReview: false
            ),
            372
        )
        XCTAssertTrue(ATHLTHReplayDataQuality.reliableSegment(
            distanceMeters: 1_250,
            paceSecondsPerKilometer: 372,
            activity: .running
        ))
    }

    func testIndoorStrengthAndTreadmillAreNotFlaggedForMissingGPS() {
        XCTAssertFalse(ATHLTHReplayDataQuality.needsReview(
            activity: .strength,
            isIndoor: true,
            duration: 90 * 60,
            distanceMeters: nil
        ))
        XCTAssertFalse(ATHLTHReplayDataQuality.needsReview(
            activity: .running,
            isIndoor: true,
            duration: 80 * 60,
            distanceMeters: 0
        ))
        XCTAssertNil(ATHLTHReplayDataQuality.usablePace(
            duration: 80 * 60,
            distanceMeters: nil,
            activity: .running,
            requiresReview: false
        ))
    }

    func testSlowButPlausibleWalkingIsNotFlagged() {
        XCTAssertFalse(ATHLTHReplayDataQuality.needsReview(
            activity: .walking,
            isIndoor: false,
            duration: 3_600,
            distanceMeters: 1_500
        ))
        XCTAssertTrue(ATHLTHReplayDataQuality.plausiblePace(
            2_400, activity: .walking
        ))
    }

    func testUnreliableTinySegmentsAndImpossiblePaceAreRejected() {
        XCTAssertFalse(ATHLTHReplayDataQuality.reliableSegment(
            distanceMeters: 20,
            paceSecondsPerKilometer: 500,
            activity: .running
        ))
        XCTAssertFalse(ATHLTHReplayDataQuality.reliableSegment(
            distanceMeters: 1_000,
            paceSecondsPerKilometer: 1_000_000,
            activity: .running
        ))
        XCTAssertFalse(ATHLTHReplayDataQuality.plausiblePace(
            .infinity, activity: .running
        ))
    }

    func testHistoricComparisonRequiresSimilarMeasuredDistance() {
        XCTAssertTrue(ATHLTHReplayDataQuality.isComparableDistance(
            current: 10_000, previous: 10_400
        ))
        XCTAssertFalse(ATHLTHReplayDataQuality.isComparableDistance(
            current: 10_000, previous: 5_000
        ))
        XCTAssertFalse(ATHLTHReplayDataQuality.isComparableDistance(
            current: 20, previous: 20
        ))
    }
}
