import CoreLocation
import XCTest
@testable import ATHLTH

final class IPhoneWorkoutLiveRouteMetricsTests: XCTestCase {
    @MainActor
    func testBuildsKilometerSplitsFromRecordedGPSPoints() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = makePoints(
            count: 22,
            start: start,
            secondsBetween: 30,
            metersBetween: 100,
            altitudeStep: 0
        )

        let workout = PhoneWorkout(
            walking: false,
            start: start,
            resumedAt: nil,
            lastCheckpoint: start,
            points: points
        )

        let metrics =
            IPhoneWorkoutLiveRouteMetrics.calculate(
                workout: workout,
                splitMeters: 1_000
            )

        XCTAssertGreaterThanOrEqual(
            metrics.splits.count,
            2
        )
        XCTAssertEqual(
            metrics.splits[0].seconds,
            300,
            accuracy: 8
        )
        XCTAssertEqual(
            metrics.splits[1].seconds,
            300,
            accuracy: 8
        )
    }

    @MainActor
    func testPauseGapDoesNotBecomeSplitDistance() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = makePoints(
            count: 12,
            start: start,
            secondsBetween: 30,
            metersBetween: 100,
            altitudeStep: 0
        )

        let workout = PhoneWorkout(
            walking: false,
            start: start,
            resumedAt: nil,
            lastCheckpoint: start,
            pauses: [
                PhoneWorkoutPauseInterval(
                    startedAt:
                        start.addingTimeInterval(145),
                    endedAt:
                        start.addingTimeInterval(185)
                )
            ],
            points: points
        )

        let metrics =
            IPhoneWorkoutLiveRouteMetrics.calculate(
                workout: workout,
                splitMeters: 1_000
            )

        XCTAssertTrue(metrics.splits.isEmpty)
    }

    @MainActor
    func testElevationGainIsDerivedWithoutUsingRawNoiseDirectly() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = makePoints(
            count: 18,
            start: start,
            secondsBetween: 20,
            metersBetween: 70,
            altitudeStep: 2
        )

        let workout = PhoneWorkout(
            walking: false,
            start: start,
            resumedAt: nil,
            lastCheckpoint: start,
            points: points
        )

        let metrics =
            IPhoneWorkoutLiveRouteMetrics.calculate(
                workout: workout,
                splitMeters: 1_000
            )

        XCTAssertGreaterThan(
            metrics.elevationGainMeters,
            5
        )
    }

    private func makePoints(
        count: Int,
        start: Date,
        secondsBetween: TimeInterval,
        metersBetween: Double,
        altitudeStep: Double
    ) -> [PhoneRoutePoint] {
        let metersPerDegreeLongitude =
            111_319.49079327357
        let degreeStep =
            metersBetween /
            metersPerDegreeLongitude

        return (0..<count).map { index in
            let location = CLLocation(
                coordinate:
                    CLLocationCoordinate2D(
                        latitude: 0,
                        longitude:
                            Double(index) *
                            degreeStep
                    ),
                altitude:
                    Double(index) *
                    altitudeStep,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                timestamp:
                    start.addingTimeInterval(
                        Double(index) *
                        secondsBetween
                    )
            )

            return PhoneRoutePoint(location)
        }
    }
}
