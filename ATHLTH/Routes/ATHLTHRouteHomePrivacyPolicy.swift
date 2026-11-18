import CoreLocation
import Foundation
import MapKit

/// Keeps the owner's canonical GPS trace intact. The returned route is a
/// *public-facing copy* only, used immediately before cloud publication.
/// A home endpoint is selected explicitly by the athlete, never inferred
/// from their current GPS position.
enum ATHLTHRouteHomePrivacyPolicy {
    static let hiddenRadiusMeters: CLLocationDistance = 250
    private static let safetyMarginMeters: CLLocationDistance = 5

    static func sharedVersion(of route: TrainingRoute) -> TrainingRoute? {
        let hideStart = route.hideSharedStartNearHome == true
        let hideEnd = route.hideSharedEndNearHome == true
        guard route.visibility != .privateOnly, hideStart || hideEnd else {
            return route
        }

        let source = route.coordinates.sorted { $0.sequence < $1.sequence }
        guard source.count >= 2, source.allSatisfy({
            CLLocationCoordinate2DIsValid($0.coordinate) &&
                $0.latitude.isFinite && $0.longitude.isFinite
        }), let first = source.first, let last = source.last else { return nil }

        let start = MKMapPoint(first.coordinate)
        let end = MKMapPoint(last.coordinate)
        let safeRadius = hiddenRadiusMeters + safetyMarginMeters

        func outsideHomeZones(_ point: RouteCoordinate) -> Bool {
            let coordinate = MKMapPoint(point.coordinate)
            return (!hideStart || coordinate.distance(to: start) >= safeRadius) &&
                (!hideEnd || coordinate.distance(to: end) >= safeRadius)
        }

        func safeSegment(_ a: RouteCoordinate, _ b: RouteCoordinate) -> Bool {
            let from = MKMapPoint(a.coordinate)
            let to = MKMapPoint(b.coordinate)
            let dx = to.x - from.x
            let dy = to.y - from.y
            let length2 = dx * dx + dy * dy
            func outside(_ home: MKMapPoint) -> Bool {
                let fraction = length2 > 0
                    ? min(1, max(0, ((home.x - from.x) * dx +
                                      (home.y - from.y) * dy) / length2))
                    : 0
                let closest = MKMapPoint(
                    x: from.x + fraction * dx,
                    y: from.y + fraction * dy
                )
                return closest.distance(to: home) >= safeRadius
            }
            return (!hideStart || outside(start)) && (!hideEnd || outside(end))
        }

        func pathLength(_ points: [RouteCoordinate]) -> CLLocationDistance {
            guard points.count >= 2 else { return 0 }
            return zip(points, points.dropFirst()).reduce(0) { total, pair in
                let first = CLLocation(latitude: pair.0.latitude,
                                       longitude: pair.0.longitude)
                let second = CLLocation(latitude: pair.1.latitude,
                                        longitude: pair.1.longitude)
                return total + first.distance(from: second)
            }
        }

        // Only retain a single uninterrupted safe section. On a loop,
        // joining two separated sections would draw a line through home.
        var current: [RouteCoordinate] = []
        var longest: [RouteCoordinate] = []
        func finishSection() {
            if pathLength(current) > pathLength(longest) {
                longest = current
            }
            current = []
        }

        for point in source {
            guard outsideHomeZones(point) else {
                finishSection()
                continue
            }
            if let previous = current.last, !safeSegment(previous, point) {
                finishSection()
            }
            current.append(point)
        }
        finishSection()
        let lengthMeters = pathLength(longest)
        guard longest.count >= 2, lengthMeters >= 1 else { return nil }

        var shared = route
        shared.coordinates = longest.enumerated().map { index, point in
            var copy = point
            copy.sequence = index
            return copy
        }
        shared.distanceKilometers = lengthMeters / 1_000
        // The original elevation and travel-time estimates no longer
        // describe the cropped geometry.
        shared.elevationGainMeters = nil
        shared.expectedTravelTimeSeconds = nil

        if hideStart {
            if let name = route.startName, !name.isEmpty {
                shared.title = shared.title.replacingOccurrences(
                    of: name, with: "Skjult start", options: [.caseInsensitive]
                )
            }
            shared.startName = "Skjult start"
        }
        if hideEnd {
            if let name = route.endName, !name.isEmpty {
                shared.title = shared.title.replacingOccurrences(
                    of: name, with: "Skjult slutt", options: [.caseInsensitive]
                )
            }
            shared.endName = "Skjult slutt"
        }
        // Home selections are local-only and must not enter public JSON.
        shared.hideSharedStartNearHome = nil
        shared.hideSharedEndNearHome = nil
        return shared
    }
}

enum ATHLTHRouteHomePrivacyError: LocalizedError {
    case insufficientSafeRoute

    var errorDescription: String? {
        switch self {
        case .insufficientSafeRoute:
            return ATHLTHLocalization.choose(
                english: "There is not enough route outside the selected 250 m home zone(s) to share safely. Change the route or keep it private.",
                norwegian: "Det er ikke nok rute utenfor de valgte 250 m-sonene ved hjemmet til å dele trygt. Endre ruten eller behold den privat."
            )
        }
    }
}
