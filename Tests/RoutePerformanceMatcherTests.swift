import CoreLocation
import XCTest
@testable import ATHLTH

final class RoutePerformanceMatcherTests:
    XCTestCase {
    private func location(
        latitude: Double,
        longitude: Double
    ) -> CLLocation {
        CLLocation(
            latitude: latitude,
            longitude: longitude
        )
    }

    private var referenceRoute:
        [CLLocation] {
        // Roughly 2 km east/west at Trondheim latitude.
        [
            location(
                latitude: 63.4305,
                longitude: 10.3950
            ),
            location(
                latitude: 63.4305,
                longitude: 10.4050
            ),
            location(
                latitude: 63.4305,
                longitude: 10.4150
            ),
            location(
                latitude: 63.4305,
                longitude: 10.4250
            ),
            location(
                latitude: 63.4305,
                longitude: 10.4350
            )
        ]
    }

    func testMatchingRouteScoresVeryHigh() {
        let result =
            RoutePerformanceMatcher
                .analyze(
                    reference:
                        referenceRoute,
                    actual:
                        referenceRoute
                )

        XCTAssertNotNil(result)
        XCTAssertGreaterThan(
            result?.routeMatchPercent ??
                0,
            98
        )
        XCTAssertLessThan(
            result?
                .averageDeviationMeters ??
                999,
            2
        )
    }

    func testReverseDirectionStillMatches() {
        let result =
            RoutePerformanceMatcher
                .analyze(
                    reference:
                        referenceRoute,
                    actual:
                        Array(
                            referenceRoute
                                .reversed()
                        )
                )

        XCTAssertGreaterThan(
            result?.routeMatchPercent ??
                0,
            98
        )
    }

    func testLargeExcursionIsPenalizedEvenWhenReferenceIsCovered() {
        let route =
            referenceRoute
        let midpoint =
            route[2]

        let actual = [
            route[0],
            route[1],
            midpoint,
            location(
                latitude:
                    midpoint.coordinate
                        .latitude +
                    0.0072,
                longitude:
                    midpoint.coordinate
                        .longitude
            ),
            midpoint,
            route[3],
            route[4]
        ]

        let result =
            RoutePerformanceMatcher
                .analyze(
                    reference: route,
                    actual: actual
                )

        XCTAssertNotNil(result)

        // The legacy one-way matcher scored this pattern close to 100%
        // because every reference point is visited. The corrected matcher
        // must penalize the large off-route excursion itself.
        XCTAssertLessThan(
            result?.routeMatchPercent ??
                100,
            75
        )
        XCTAssertGreaterThan(
            result?
                .maxDeviationMeters ??
                0,
            500
        )
    }

    func testParallelStreetOutsideToleranceScoresLow() {
        let actual =
            referenceRoute.map {
                location(
                    latitude:
                        $0.coordinate.latitude +
                        0.00135,
                    longitude:
                        $0.coordinate.longitude
                )
            }

        let result =
            RoutePerformanceMatcher
                .analyze(
                    reference:
                        referenceRoute,
                    actual:
                        actual
                )

        XCTAssertLessThan(
            result?.routeMatchPercent ??
                100,
            20
        )
        XCTAssertGreaterThan(
            result?
                .averageDeviationMeters ??
                0,
            100
        )
    }
}
