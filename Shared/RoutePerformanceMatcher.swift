import CoreLocation
import Foundation

struct RoutePerformanceMatchMetrics: Hashable {
    let routeMatchPercent: Double
    let averageDeviationMeters: Double
    let maxDeviationMeters: Double
}

enum RoutePerformanceMatcher {
    // Route matching should represent both questions:
    // 1. Did the workout cover the intended route?
    // 2. Did the workout itself stay on the intended route?
    //
    // The old implementation only answered the first question, which meant
    // a large detour could still score highly as long as the runner later
    // passed close to most reference points.
    static func analyze(
        reference: [CLLocation],
        actual: [CLLocation]
    ) -> RoutePerformanceMatchMetrics? {
        guard reference.count >= 2,
              actual.count >= 2
        else {
            return nil
        }

        let referenceSamples =
            resampled(
                reference,
                maximumSamples: 260,
                minimumSpacingMeters: 20
            )
        let actualSamples =
            resampled(
                actual,
                maximumSamples: 260,
                minimumSpacingMeters: 20
            )

        guard referenceSamples.count >= 2,
              actualSamples.count >= 2
        else {
            return nil
        }

        let referenceToActual =
            nearestPolylineDistances(
                samples: referenceSamples,
                polyline: actual
            )
        let actualToReference =
            nearestPolylineDistances(
                samples: actualSamples,
                polyline: reference
            )

        guard !referenceToActual.isEmpty,
              !actualToReference.isEmpty
        else {
            return nil
        }

        let referenceCoverage =
            meanMatchScore(
                distances: referenceToActual
            )
        let actualCoverage =
            meanMatchScore(
                distances: actualToReference
            )

        // Harmonic mean deliberately penalizes an asymmetric match. A run
        // that touches most of the planned route but also contains a large
        // off-route excursion should not receive a high "followed" score.
        let bidirectionalCoverage: Double
        if referenceCoverage <= 0 ||
            actualCoverage <= 0 {
            bidirectionalCoverage = 0
        } else {
            bidirectionalCoverage =
                2 *
                referenceCoverage *
                actualCoverage /
                (
                    referenceCoverage +
                    actualCoverage
                )
        }

        // Path-length similarity catches shortcuts and large detours even
        // when a dense urban route passes close to itself.
        let referenceLength =
            polylineLength(reference)
        let actualLength =
            polylineLength(actual)
        let lengthSimilarity: Double
        if referenceLength > 0,
           actualLength > 0 {
            lengthSimilarity =
                min(
                    referenceLength,
                    actualLength
                ) /
                max(
                    referenceLength,
                    actualLength
                )
        } else {
            lengthSimilarity = 0
        }

        // Keep length as a supporting penalty rather than the primary test:
        // Health/GPS distance can vary slightly on otherwise identical runs.
        let lengthPenalty =
            pow(
                min(
                    max(
                        lengthSimilarity,
                        0
                    ),
                    1
                ),
                0.35
            )

        let routeMatchPercent =
            min(
                max(
                    bidirectionalCoverage *
                        lengthPenalty *
                        100,
                    0
                ),
                100
            )

        let finiteActualDeviations =
            actualToReference
                .filter(\.isFinite)
        guard !finiteActualDeviations.isEmpty
        else {
            return nil
        }

        // "Deviation" is defined from the user's actual travelled path to
        // the planned route. The old direction (reference -> workout) could
        // hide large extra excursions.
        let averageDeviation =
            finiteActualDeviations
                .reduce(0, +) /
                Double(
                    finiteActualDeviations.count
                )
        let maximumDeviation =
            finiteActualDeviations.max() ?? 0

        return RoutePerformanceMatchMetrics(
            routeMatchPercent:
                routeMatchPercent,
            averageDeviationMeters:
                max(
                    averageDeviation,
                    0
                ),
            maxDeviationMeters:
                max(
                    maximumDeviation,
                    0
                )
        )
    }

    private static func meanMatchScore(
        distances: [Double]
    ) -> Double {
        let finite =
            distances.filter(\.isFinite)
        guard !finite.isEmpty else {
            return 0
        }

        return finite
            .reduce(0) {
                $0 + matchScore(
                    distanceMeters: $1
                )
            } /
            Double(finite.count)
    }

    private static func matchScore(
        distanceMeters: Double
    ) -> Double {
        let distance =
            max(distanceMeters, 0)

        // Full credit inside normal outdoor GPS noise. Parallel streets and
        // meaningful urban detours then lose credit progressively instead
        // of being counted as a binary match merely because they are <80 m.
        if distance <= 20 {
            return 1
        }

        if distance <= 60 {
            let fraction =
                (distance - 20) / 40
            return 1 - 0.75 * fraction
        }

        if distance <= 100 {
            let fraction =
                (distance - 60) / 40
            return 0.25 * (1 - fraction)
        }

        return 0
    }

    private static func resampled(
        _ locations: [CLLocation],
        maximumSamples: Int,
        minimumSpacingMeters: Double
    ) -> [CLLocation] {
        guard locations.count >= 2 else {
            return locations
        }

        let total =
            polylineLength(locations)
        guard total > 0 else {
            return [
                locations.first!,
                locations.last!
            ]
        }

        let spacing =
            max(
                minimumSpacingMeters,
                total /
                    Double(
                        max(
                            maximumSamples - 1,
                            1
                        )
                    )
            )

        var samples: [CLLocation] = [
            locations[0]
        ]
        var targetDistance = spacing
        var accumulated = 0.0

        for index in 1..<locations.count {
            let start =
                locations[index - 1]
            let end =
                locations[index]
            let segmentLength =
                start.distance(from: end)

            guard segmentLength > 0 else {
                continue
            }

            while targetDistance <=
                    accumulated +
                    segmentLength,
                  samples.count <
                    maximumSamples - 1 {
                let fraction =
                    (
                        targetDistance -
                        accumulated
                    ) /
                    segmentLength
                samples.append(
                    interpolatedLocation(
                        from: start,
                        to: end,
                        fraction: fraction
                    )
                )
                targetDistance += spacing
            }

            accumulated += segmentLength
        }

        if let last = locations.last,
           (
                samples.last?
                    .distance(
                        from: last
                    ) ??
                Double
                    .greatestFiniteMagnitude
           ) > 1 {
            samples.append(last)
        }

        return samples
    }

    private static func polylineLength(
        _ locations: [CLLocation]
    ) -> Double {
        guard locations.count >= 2 else {
            return 0
        }

        var total = 0.0
        for index in 1..<locations.count {
            total +=
                locations[index - 1]
                    .distance(
                        from:
                            locations[index]
                    )
        }
        return total
    }

    private static func nearestPolylineDistances(
        samples: [CLLocation],
        polyline: [CLLocation]
    ) -> [Double] {
        guard polyline.count >= 2 else {
            return []
        }

        return samples.map { sample in
            var nearest =
                Double
                    .greatestFiniteMagnitude

            for index in 1..<polyline.count {
                nearest =
                    min(
                        nearest,
                        distance(
                            from: sample,
                            toSegmentStart:
                                polyline[index - 1],
                            end:
                                polyline[index]
                        )
                    )
            }

            return nearest
        }
    }

    private static func distance(
        from point: CLLocation,
        toSegmentStart start: CLLocation,
        end: CLLocation
    ) -> Double {
        // Local equirectangular projection is sufficiently accurate for a
        // route segment and avoids nearest-vertex errors on sparse routes.
        let earthRadius =
            6_371_000.0
        let latitude0 =
            point.coordinate.latitude *
            .pi / 180
        let cosine =
            cos(latitude0)

        func xy(
            _ location: CLLocation
        ) -> (x: Double, y: Double) {
            let latitude =
                location.coordinate.latitude *
                .pi / 180
            let longitude =
                location.coordinate.longitude *
                .pi / 180
            let originLongitude =
                point.coordinate.longitude *
                .pi / 180

            return (
                (longitude -
                    originLongitude) *
                    cosine *
                    earthRadius,
                (latitude - latitude0) *
                    earthRadius
            )
        }

        let a = xy(start)
        let b = xy(end)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared =
            dx * dx + dy * dy

        guard lengthSquared > 0 else {
            return point.distance(
                from: start
            )
        }

        let t =
            min(
                max(
                    (
                        -a.x * dx -
                        a.y * dy
                    ) /
                    lengthSquared,
                    0
                ),
                1
            )
        let closestX =
            a.x + t * dx
        let closestY =
            a.y + t * dy

        return sqrt(
            closestX * closestX +
            closestY * closestY
        )
    }

    private static func interpolatedLocation(
        from start: CLLocation,
        to end: CLLocation,
        fraction: Double
    ) -> CLLocation {
        let t =
            min(
                max(fraction, 0),
                1
            )

        return CLLocation(
            latitude:
                start.coordinate.latitude +
                (
                    end.coordinate.latitude -
                    start.coordinate.latitude
                ) * t,
            longitude:
                start.coordinate.longitude +
                (
                    end.coordinate.longitude -
                    start.coordinate.longitude
                ) * t
        )
    }
}
