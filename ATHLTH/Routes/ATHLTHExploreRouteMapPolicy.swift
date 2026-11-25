import CoreLocation
import Foundation
import MapKit

/// Map-only route picking and signposting. This must never modify the saved
/// track, its GPS evidence or the start/finish used by the workout engine.
enum ATHLTHExploreRouteMapPolicy {
    struct Candidate {
        let id: UUID
        let points: [CLLocationCoordinate2D]
    }

    /// Convert a tap to the closest actual *segment*, not the closest
    /// downsampled GPS point. A fixed 240 m radius used to select nearby
    /// unrelated streets and overlapping routes at normal city zoom levels.
    static func nearestRouteID(
        to coordinate: CLLocationCoordinate2D,
        candidates: [Candidate],
        toleranceMeters: Double,
        preferredID: UUID? = nil
    ) -> UUID? {
        guard CLLocationCoordinate2DIsValid(coordinate),
              toleranceMeters.isFinite, toleranceMeters > 0 else { return nil }
        let threshold = min(65, max(6, toleranceMeters))
        let target = MKMapPoint(coordinate)
        let metersPerPoint = MKMetersPerMapPointAtLatitude(coordinate.latitude)
        guard metersPerPoint.isFinite, metersPerPoint > 0 else { return nil }

        var matched: [(id: UUID, meters: Double)] = []
        for candidate in candidates {
            guard candidate.points.count >= 2 else { continue }
            var best = Double.infinity
            var previous: MKMapPoint?
            for value in candidate.points {
                guard CLLocationCoordinate2DIsValid(value) else {
                    previous = nil
                    continue
                }
                let current = MKMapPoint(value)
                if let previous {
                    let dx = current.x - previous.x
                    let dy = current.y - previous.y
                    let squared = dx * dx + dy * dy
                    let fraction = squared > 0
                        ? min(1, max(0, ((target.x - previous.x) * dx +
                                        (target.y - previous.y) * dy) / squared))
                        : 0
                    let nearestX = previous.x + fraction * dx
                    let nearestY = previous.y + fraction * dy
                    let meters = hypot(target.x - nearestX, target.y - nearestY) *
                        metersPerPoint
                    best = min(best, meters)
                }
                previous = current
            }
            if best <= threshold { matched.append((candidate.id, best)) }
        }
        guard let closest = matched.min(by: { $0.meters < $1.meters })
        else { return nil }

        // Keep the already highlighted route on overlapping lines unless a
        // different route is *clearly* closer. Other routes remain selectable
        // through their own exact-ID annotation buttons.
        if let preferredID,
           let preferred = matched.first(where: { $0.id == preferredID }),
           preferred.meters <= closest.meters + min(5, threshold * 0.25) {
            return preferredID
        }
        return closest.id
    }

    /// Turns are selected from *actual changes in the route geometry*, not
    /// a single arbitrary index a third of the way through the polyline.
    /// These are visual travel-direction hints, not turn-by-turn navigation.
    struct Cue: Identifiable {
        let id: Int
        let coordinate: CLLocationCoordinate2D
        /// North = 0 degrees, clockwise positive.
        let bearingDegrees: Double
    }

    static func directionCues(
        for points: [CLLocationCoordinate2D],
        maximum: Int = 7
    ) -> [Cue] {
        guard points.count >= 3, maximum > 0,
              points.allSatisfy(CLLocationCoordinate2DIsValid) else { return [] }

        struct Turn {
            let index: Int
            let degrees: Double
            let coordinate: CLLocationCoordinate2D
            let bearing: Double
        }

        let locations = points.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        var accumulated = [Double](repeating: 0, count: points.count)
        for i in 1..<points.count {
            accumulated[i] = accumulated[i - 1] +
                locations[i].distance(from: locations[i - 1])
        }
        let total = accumulated[points.count - 1]
        guard total >= 160 else { return [] }

        var turns: [Turn] = []
        for index in 1..<(points.count - 1) {
            let preceding = locations[index].distance(from: locations[index - 1])
            let following = locations[index + 1].distance(from: locations[index])
            guard preceding >= 16, following >= 16,
                  accumulated[index] >= 65,
                  total - accumulated[index] >= 65 else { continue }
            let inbound = bearing(from: points[index - 1], to: points[index])
            let outbound = bearing(from: points[index], to: points[index + 1])
            let change = abs((outbound - inbound + 540)
                .truncatingRemainder(dividingBy: 360) - 180)
            guard change >= 32 else { continue }
            let distance = min(12, following * 0.3)
            let fraction = min(0.45, distance / following)
            let marker = CLLocationCoordinate2D(
                latitude: points[index].latitude +
                    (points[index + 1].latitude - points[index].latitude) * fraction,
                longitude: points[index].longitude +
                    (points[index + 1].longitude - points[index].longitude) * fraction
            )
            turns.append(Turn(index: index, degrees: change,
                              coordinate: marker, bearing: outbound))
        }

        // Prioritize meaningful junctions, keep visual separation, and cap
        // annotations for long routes. Do not pretend that every turn is an
        // actual surveyed road junction.
        let ranked = turns.sorted { $0.degrees > $1.degrees }
        var accepted: [Turn] = []
        for turn in ranked {
            guard accepted.count < min(maximum, 9) else { break }
            let location = CLLocation(latitude: turn.coordinate.latitude,
                                      longitude: turn.coordinate.longitude)
            if accepted.allSatisfy({
                location.distance(from: CLLocation(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude
                )) >= 90
            }) {
                accepted.append(turn)
            }
        }
        return accepted.sorted { $0.index < $1.index }.map {
            Cue(id: $0.index, coordinate: $0.coordinate,
                bearingDegrees: $0.bearing)
        }
    }

    private static func bearing(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> Double {
        let midLatitude = (a.latitude + b.latitude) * .pi / 360
        let east = (b.longitude - a.longitude) * cos(midLatitude)
        let north = b.latitude - a.latitude
        return atan2(east, north) * 180 / .pi
    }

    static func estimatedTimes(
        distanceKilometers: Double,
        publicWalkSeconds: TimeInterval? = nil,
        publicRunSeconds: TimeInterval? = nil
    ) -> (walk: TimeInterval, run: TimeInterval)? {
        guard let walking = ATHLTHRouteDetailsPolicy.estimateSeconds(
            distanceKilometers: distanceKilometers, running: false),
              let running = ATHLTHRouteDetailsPolicy.estimateSeconds(
                distanceKilometers: distanceKilometers, running: true) else {
            return nil
        }
        func validated(_ value: TimeInterval?) -> TimeInterval? {
            guard let value, value.isFinite, value > 0 else { return nil }
            return value
        }
        return (walk: validated(publicWalkSeconds) ?? walking,
                run: validated(publicRunSeconds) ?? running)
    }

    /// Never infer asphalt/gravel from Apple Maps' visual style. Show the
    /// owner's percentages or the public trail's sourced surface text.
    static func surfaceLabel(
        percentages: [String: Int]?,
        publishedSummary: String? = nil
    ) -> String {
        let cleaned = ATHLTHRouteDetailsPolicy.cleanedSurfaces(percentages ?? [:])
        if !cleaned.isEmpty {
            let values = ATHLTHRouteSurface.allCases.compactMap { surface -> String? in
                guard let percent = cleaned[surface.rawValue], percent > 0 else {
                    return nil
                }
                return "\(surface.title) \(percent) %"
            }
            let unclassified = ATHLTHRouteDetailsPolicy.unclassifiedPercent(cleaned)
            let unknown = unclassified > 0
                ? ATHLTHLocalization.choose(
                    english: "Unknown \(unclassified) %",
                    norwegian: "Ukjent \(unclassified) %"
                ) : nil
            return (values + (unknown.map { [$0] } ?? [])).joined(separator: " · ")
        }
        if let summary = publishedSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return summary
        }
        return ATHLTHLocalization.choose(
            english: "Surface unknown", norwegian: "Underlag ukjent"
        )
    }
}


/// Layout depends on the actual Studio detail width, not device model.
enum ATHLTHExploreStudioLayoutPolicy {
    static func usesWideMap(width: CGFloat) -> Bool {
        width.isFinite && width >= 700
    }

    static func previewWidth(width: CGFloat) -> CGFloat? {
        usesWideMap(width: width) ? min(480, width * 0.48) : nil
    }

    static func controlsWidth(width: CGFloat) -> CGFloat? {
        usesWideMap(width: width) ? min(680, width - 100) : nil
    }
}
