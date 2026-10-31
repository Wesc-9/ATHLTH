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

    var useDistance = true
    var distanceKilometers = 5.0
    var useDuration = false
    var durationMinutes = 30
    var paceMinutesPerKilometer = 6.0
    var surface: Surface = .mixed
    var setting: Setting = .any
    var startMode: StartMode = .current
    var startRadiusKilometers = 2.0
    var isLoop = true
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
        case invalidLocation, noNearbyStart, noWalkingRoute

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
                    english: "Apple Maps found no connected walking route matching this area. Try another start or distance.",
                    norwegian: "Apple Maps fant ingen sammenhengende gangbar rute her. Prøv et annet startsted eller distanse."
                )
            }
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
        let start = try await resolvedStart(brief: brief, location: location.coordinate)
        let bearings: [Double] = [20, 145, 270]
        var suggestions: [ATHLTHCoachRouteSuggestion] = []

        for (index, bearing) in bearings.enumerated() {
            // A road network is longer than geometric straight lines.
            let target = brief.targetMeters
            let radius = max(160, min(8000, target / (brief.isLoop ? 4.0 : 2.55)))
            let p1 = offset(from: start, distance: radius, bearing: bearing)
            let points: [CLLocationCoordinate2D]
            if brief.isLoop {
                let p2 = offset(from: start, distance: radius,
                                bearing: bearing + 105)
                points = [start, p1, p2, start]
            } else {
                points = [start, p1]
            }
            do {
                var coordinates: [CLLocationCoordinate2D] = []
                var meters = 0.0
                for pair in zip(points, points.dropFirst()) {
                    let segment = try await walkingLeg(from: pair.0, to: pair.1)
                    if coordinates.isEmpty {
                        coordinates.append(contentsOf: segment.coordinates)
                    } else {
                        coordinates.append(contentsOf: segment.coordinates.dropFirst())
                    }
                    meters += segment.distance
                }
                if !brief.isLoop {
                    // Retrace an actually calculated route, not a guessed
                    // direct return path on unknown roads.
                    coordinates += Array(coordinates.dropLast().reversed())
                    meters *= 2
                }
                guard coordinates.count >= 2, meters.isFinite, meters > 500 else { continue }
                let minutes = meters / 1000 * brief.paceMinutesPerKilometer
                let startMeters = location.distance(from: CLLocation(
                    latitude: start.latitude, longitude: start.longitude))
                let distanceError = abs(meters - target) / target
                let timeError = brief.useDuration
                    ? abs(minutes - Double(brief.durationMinutes)) /
                        max(Double(brief.durationMinutes), 1) : 0
                let score = distanceError + timeError * 0.35 +
                    Double(index) * 0.002
                suggestions.append(ATHLTHCoachRouteSuggestion(
                    coordinates: coordinates, start: start,
                    distanceMeters: meters,
                    predictedRunMinutes: minutes,
                    distanceFromUserMeters: startMeters,
                    score: score, variation: index + 1
                ))
            } catch {
                // Routing coverage differs by region. A failed direction
                // candidate must not turn into a straight-line "trail".
                continue
            }
        }
        guard !suggestions.isEmpty else { throw GeneratorError.noWalkingRoute }
        return suggestions.sorted { $0.score < $1.score }
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
