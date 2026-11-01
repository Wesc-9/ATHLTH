import CoreLocation
import Foundation
@preconcurrency import MapKit

/// A local, consent-free route brief. The map provider computes the geometry;
/// AI text never becomes route coordinates or a claimed surface measurement.
struct ATHLTHCoachRouteBrief: Equatable {
    enum StartMode: String, CaseIterable, Identifiable {
        case current, nearby
        var id: String { rawValue }
        var title: String {
            switch self {
            case .current: return ATHLTHLocalization.choose(english: "My location", norwegian: "Der jeg er")
            case .nearby: return ATHLTHLocalization.choose(english: "Nearby start", norwegian: "Start i nærheten")
            }
        }
    }

    enum Surface: String, CaseIterable, Identifiable {
        case mixed, asphalt, gravel, path, mountain
        var id: String { rawValue }
        var title: String {
            switch self {
            case .mixed: return ATHLTHLocalization.choose(english: "Mixed", norwegian: "Blandet")
            case .asphalt: return "Asfalt"
            case .gravel: return "Grus"
            case .path: return ATHLTHLocalization.choose(english: "Trail", norwegian: "Sti")
            case .mountain: return ATHLTHLocalization.choose(english: "Mountain hike", norwegian: "Fjelltur")
            }
        }
    }

    enum Setting: String, CaseIterable, Identifiable {
        case any, streets, central, quietNature
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: return ATHLTHLocalization.choose(english: "No preference", norwegian: "Ingen preferanse")
            case .streets: return ATHLTHLocalization.choose(english: "Near roads", norwegian: "Nær veier")
            case .central: return ATHLTHLocalization.choose(english: "Near city centre", norwegian: "Nær sentrum")
            case .quietNature: return ATHLTHLocalization.choose(english: "Quiet nature", norwegian: "Rolig natur")
            }
        }
    }

    enum RouteShape: String, CaseIterable, Identifiable {
        case automatic, oneWay, outAndBack, loop
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: return ATHLTHLocalization.choose(
                english: "Automatic (A–B first)", norwegian: "Automatisk (A–B først)")
            case .oneWay: return ATHLTHLocalization.choose(
                english: "One way (A–B)", norwegian: "Én vei (A–B)")
            case .outAndBack: return ATHLTHLocalization.choose(
                english: "Out and back (A–B–A)", norwegian: "Tur-retur (A–B–A)")
            case .loop: return ATHLTHLocalization.choose(
                english: "Loop (return to A)", norwegian: "Rundløype (tilbake til A)")
            }
        }
    }

    var useDistance = true
    var distanceKilometers = 5.0
    var useDuration = false
    var durationMinutes = 30
    var paceMinutesPerKilometer = 6.0
    var surface: Surface = .mixed
    var setting: Setting = .any
    var startMode: StartMode = .current
    var startRadiusKilometers = 2.0
    /// Automatic attempts point-to-point first, then retraces a safe,
    /// MapKit-verified path if no sufficiently accurate one-way route exists.
    var routeShape: RouteShape = .automatic
    /// Compatibility with existing sources that explicitly select a loop.
    var isLoop: Bool {
        get { routeShape == .loop }
        set { routeShape = newValue ? .loop : .outAndBack }
    }
    var avoidBusyRoads = true
    var preferLessClimbing = true

    var targetMeters: Double {
        if useDistance { return distanceKilometers * 1000 }
        return (Double(durationMinutes) / paceMinutesPerKilometer) * 1000
    }

    var validationMessage: String? {
        guard useDistance || useDuration else {
            return ATHLTHLocalization.choose(
                english: "Select distance, duration or both.",
                norwegian: "Velg distanse, tid eller begge deler."
            )
        }
        guard targetMeters.isFinite, (800...30000).contains(targetMeters) else {
            return ATHLTHLocalization.choose(
                english: "Choose a route between 0.8 and 30 km.",
                norwegian: "Velg en rute på 0,8–30 km."
            )
        }
        return nil
    }
}

struct ATHLTHCoachRouteSuggestion: Identifiable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let start: CLLocationCoordinate2D
    let distanceMeters: Double
    let predictedRunMinutes: Double
    let distanceFromUserMeters: Double
    let score: Double
    let variation: Int
    let shape: ATHLTHCoachRouteBrief.RouteShape
    /// Neither MapKit's walking directions nor an AI estimate verifies surface.
    let verifiedSurfaceKilometers: [String: Double] = [:]
    var unknownSurfaceKilometers: Double { distanceMeters / 1000 }
}

/// Offers a small number of verified MapKit pedestrian geometries and
/// evaluates the *actual* returned distance instead of sketching a circle
/// or inventing an asphalt/gravel split. MapKit is not a trail routing engine.
@MainActor
enum ATHLTHCoachRouteGenerator {
    enum GeneratorError: LocalizedError {
        case invalidLocation, noNearbyStart, noWalkingRoute, noDistanceMatch

        var errorDescription: String? {
            switch self {
            case .invalidLocation:
                return ATHLTHLocalization.choose(
                    english: "Allow location access to find a nearby route.",
                    norwegian: "Tillat posisjonstilgang for å finne ruter i nærheten."
                )
            case .noNearbyStart:
                return ATHLTHLocalization.choose(
                    english: "No suitable start found in your chosen radius. Try a wider radius or start here.",
                    norwegian: "Fant ikke et egnet startsted innen radiusen. Øk radiusen eller start der du er."
                )
            case .noWalkingRoute:
                return ATHLTHLocalization.choose(
                    english: "Apple Maps could not find a connected walking route here. Try another start or distance.",
                    norwegian: "Apple Maps fant ingen sammenhengende gangbar rute her. Prøv et annet startsted eller distanse."
                )
            case .noDistanceMatch:
                return ATHLTHLocalization.choose(
                    english: "No walking route was found within 5% of your requested distance. No longer route was selected. Try another start, route type or distance.",
                    norwegian: "Fant ingen gangbar rute innenfor 5 % av ønsket distanse. Vi viser ikke lengre ruter. Prøv et annet startsted, en annen rutetype eller distanse."
                )
            }
        }
    }

    /// Only MapKit's measured, actual route length is eligible. This hard
    /// filter is applied before display and again when the route is saved.
    static func matchesRequestedDistance(
        actualMeters: Double, targetMeters: Double
    ) -> Bool {
        guard actualMeters.isFinite, targetMeters.isFinite,
              actualMeters > 0, targetMeters > 0 else { return false }
        return abs(actualMeters - targetMeters) <= targetMeters * 0.05
    }

    /// Bounded geometry correction for a new MapKit request. Do not alter the
    /// returned polyline to fake the desired length.
    static func tunedRadius(
        previousRadius: Double, actualMeters: Double, targetMeters: Double
    ) -> Double {
        guard previousRadius.isFinite, actualMeters.isFinite,
              actualMeters > 0, targetMeters.isFinite, targetMeters > 0 else {
            return previousRadius
        }
        let ratio = min(max(targetMeters / actualMeters, 0.55), 1.65)
        return min(max(previousRadius * ratio, 100), 25_000)
    }

    static func preferredShapes(
        for preference: ATHLTHCoachRouteBrief.RouteShape
    ) -> [ATHLTHCoachRouteBrief.RouteShape] {
        switch preference {
        case .automatic: return [.oneWay, .outAndBack]
        case .oneWay: return [.oneWay]
        case .outAndBack: return [.outAndBack]
        case .loop: return [.loop]
        }
    }

    static func generate(
        brief: ATHLTHCoachRouteBrief,
        location: CLLocation
    ) async throws -> [ATHLTHCoachRouteSuggestion] {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 500,
              CLLocationCoordinate2DIsValid(location.coordinate) else {
            throw GeneratorError.invalidLocation
        }
        guard brief.validationMessage == nil else {
            throw GeneratorError.noDistanceMatch
        }
        let start = try await resolvedStart(brief: brief, location: location.coordinate)
        let userDistance = location.distance(from: CLLocation(
            latitude: start.latitude, longitude: start.longitude))
        let target = brief.targetMeters
        let bearings: [Double] = [20, 105, 190, 275, 335]
        var suggestions: [ATHLTHCoachRouteSuggestion] = []
        var obtainedWalkingDirections = false

        // One-way A–B is preferred. Automatic mode only tries A–B–A when
        // fewer than three A–B proposals satisfy the requested length.
        for shape in preferredShapes(for: brief.routeShape) {
            for (index, bearing) in bearings.enumerated() {
                if suggestions.count >= 3 { break }
                let divisor: Double
                switch shape {
                case .oneWay, .automatic: divisor = 1.3
                case .outAndBack: divisor = 2.6
                case .loop: divisor = 4.25
                }
                var radius = max(120, min(22_000, target / divisor))
                var lastMeasured = Double.infinity

                // Adjust waypoints based on real pedestrian directions. A
                // distance not within ±5% never appears as a route option.
                for _ in 0..<4 {
                    if Task.isCancelled { throw CancellationError() }
                    let points = routeWaypoints(
                        from: start, radius: radius, bearing: bearing, shape: shape
                    )
                    do {
                        let traced = try await tracedRoute(waypoints: points, shape: shape)
                        obtainedWalkingDirections = true
                        let meters = traced.distance
                        guard meters.isFinite, meters > 500,
                              traced.coordinates.count >= 2 else { break }
                        if matchesRequestedDistance(
                            actualMeters: meters, targetMeters: target
                        ) {
                            let destination = traced.coordinates.last!
                            let duplicatesExisting = suggestions.contains { current in
                                guard current.shape == shape,
                                      let last = current.coordinates.last else {
                                    return false
                                }
                                return CLLocation(
                                    latitude: last.latitude, longitude: last.longitude
                                ).distance(from: CLLocation(
                                    latitude: destination.latitude,
                                    longitude: destination.longitude
                                )) < 150
                            }
                            if !duplicatesExisting {
                                let minutes = meters / 1000 * brief.paceMinutesPerKilometer
                                let distanceError = abs(meters - target) / target
                                let timeError = brief.useDuration
                                    ? abs(minutes - Double(brief.durationMinutes)) /
                                        max(Double(brief.durationMinutes), 1) : 0
                                suggestions.append(ATHLTHCoachRouteSuggestion(
                                    coordinates: traced.coordinates, start: start,
                                    distanceMeters: meters,
                                    predictedRunMinutes: minutes,
                                    distanceFromUserMeters: userDistance,
                                    score: distanceError + timeError * 0.15 +
                                        (shape == .oneWay ? 0 : 0.1) +
                                        Double(index) * 0.0001,
                                    variation: index + 1,
                                    shape: shape
                                ))
                            }
                            break
                        }
                        // Stop if the destination is disconnected or correcting
                        // the waypoint no longer changes the measured length.
                        if abs(meters - lastMeasured) < 15 { break }
                        lastMeasured = meters
                        let updated = tunedRadius(
                            previousRadius: radius,
                            actualMeters: meters,
                            targetMeters: target
                        )
                        if abs(updated - radius) < 20 { break }
                        radius = updated
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // This bearing may have no pedestrian connectivity.
                        // Try a different direction, never a straight-line route.
                        break
                    }
                }
            }
        }
        guard !suggestions.isEmpty else {
            throw obtainedWalkingDirections
                ? GeneratorError.noDistanceMatch : GeneratorError.noWalkingRoute
        }
        return suggestions.sorted { $0.score < $1.score }
    }

    private static func routeWaypoints(
        from start: CLLocationCoordinate2D,
        radius: Double,
        bearing: Double,
        shape: ATHLTHCoachRouteBrief.RouteShape
    ) -> [CLLocationCoordinate2D] {
        let destination = offset(
            from: start, distance: radius, bearing: bearing
        )
        if shape == .loop {
            let middle = offset(
                from: start, distance: radius, bearing: bearing + 110
            )
            return [start, destination, middle, start]
        }
        return [start, destination]
    }

    private static func tracedRoute(
        waypoints: [CLLocationCoordinate2D],
        shape: ATHLTHCoachRouteBrief.RouteShape
    ) async throws -> (coordinates: [CLLocationCoordinate2D], distance: Double) {
        var coordinates: [CLLocationCoordinate2D] = []
        var meters = 0.0
        for (from, to) in zip(waypoints, waypoints.dropFirst()) {
            let leg = try await walkingLeg(from: from, to: to)
            coordinates.append(contentsOf:
                coordinates.isEmpty ? leg.coordinates : Array(leg.coordinates.dropFirst())
            )
            meters += leg.distance
        }

        if shape == .outAndBack {
            // Only this explicit fallback returns over the *same verified*
            // geometry. One-way A–B must remain a genuine one-way route.
            coordinates.append(contentsOf: coordinates.dropLast().reversed())
            meters *= 2
        }
        return (coordinates, meters)
    }

    private static func resolvedStart(
        brief: ATHLTHCoachRouteBrief,
        location: CLLocationCoordinate2D
    ) async throws -> CLLocationCoordinate2D {
        guard brief.startMode == .nearby else { return location }
        let radius = brief.startRadiusKilometers * 1000
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery =
            brief.surface == .mountain || brief.surface == .path
                ? "trailhead"
                : "park entrance"
        request.region = MKCoordinateRegion(
            center: location, latitudinalMeters: max(radius * 2, 1000),
            longitudinalMeters: max(radius * 2, 1000)
        )
        let response = try await MKLocalSearch(request: request).start()
        let current = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let matches = response.mapItems.compactMap { item -> (CLLocationCoordinate2D, Double)? in
            let position = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(position) else { return nil }
            let meters = current.distance(from: CLLocation(
                latitude: position.latitude, longitude: position.longitude))
            guard meters >= 150 && meters <= radius else { return nil }
            return (position, meters)
        }.sorted { $0.1 < $1.1 }
        guard let candidate = matches.first else { throw GeneratorError.noNearbyStart }
        return candidate.0
    }

    private static func offset(
        from coordinate: CLLocationCoordinate2D,
        distance: Double, bearing: Double
    ) -> CLLocationCoordinate2D {
        let radians = bearing * .pi / 180
        let latitude = coordinate.latitude + cos(radians) * distance / 111_320
        let longitude = coordinate.longitude + sin(radians) * distance /
            max(111_320 * cos(coordinate.latitude * .pi / 180), 1000)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func walkingLeg(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) async throws -> (coordinates: [CLLocationCoordinate2D], distance: Double) {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .walking
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first, route.polyline.pointCount >= 2 else {
            throw GeneratorError.noWalkingRoute
        }
        var points = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(),
            count: route.polyline.pointCount
        )
        route.polyline.getCoordinates(
            &points, range: NSRange(location: 0, length: route.polyline.pointCount)
        )
        return (points, route.distance)
    }
}
