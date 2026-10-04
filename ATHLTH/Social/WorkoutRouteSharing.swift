import CoreLocation
import MapKit
import SwiftUI

enum WorkoutRouteSharing {
    static func preview(_ route: [CLLocation], hideStartAndEnd: Bool) -> [RouteCoordinate] {
        guard route.count >= 2, route.allSatisfy({ CLLocationCoordinate2DIsValid($0.coordinate) }),
              let first = route.first, let last = route.last else { return [] }
        var visible = route
        if hideStartAndEnd {
            // Keep one continuous safe section. Connecting separated sections could
            // draw a line back through a hidden area, including on loop routes.
            var longest: [CLLocation] = []
            var section: [CLLocation] = []
            for point in route {
                guard point.distance(from: first) >= 250, point.distance(from: last) >= 250 else {
                    if section.count > longest.count { longest = section }
                    section = []
                    continue
                }
                if let previous = section.last,
                   (!segmentIsSafe(previous, point, around: first) || !segmentIsSafe(previous, point, around: last)) {
                    if section.count > longest.count { longest = section }
                    section = []
                }
                section.append(point)
            }
            if section.count > longest.count { longest = section }
            visible = longest
        }
        guard visible.count >= 2 else { return [] }
        let step = max(1, Int(ceil(Double(visible.count) / 300)))
        let sampled = stride(from: 0, to: visible.count, by: step).map { visible[$0] }
        guard sampled.count >= 2 else { return [] }
        // Simplification must not introduce a line through either private area.
        if hideStartAndEnd {
            for (a, b) in zip(sampled, sampled.dropFirst()) {
                guard segmentIsSafe(a, b, around: first), segmentIsSafe(a, b, around: last) else { return [] }
            }
        }
        return sampled.enumerated().map { index, point in
            RouteCoordinate(latitude: point.coordinate.latitude,
                            longitude: point.coordinate.longitude,
                            altitude: nil, sequence: index)
        }
    }

    private static func segmentIsSafe(_ a: CLLocation, _ b: CLLocation, around center: CLLocation) -> Bool {
        let start = MKMapPoint(a.coordinate)
        let end = MKMapPoint(b.coordinate)
        let origin = MKMapPoint(center.coordinate)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared > 0 ? min(1, max(0, ((origin.x - start.x) * dx + (origin.y - start.y) * dy) / lengthSquared)) : 0
        let nearest = MKMapPoint(x: start.x + t * dx, y: start.y + t * dy)
        return nearest.distance(to: origin) >= 255
    }

    static func encode(_ route: [RouteCoordinate]) -> String? {
        guard route.count >= 2, route.count <= 300,
              route.allSatisfy({ CLLocationCoordinate2DIsValid($0.coordinate) }),
              let data = try? JSONEncoder().encode(route) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ value: String?) -> [RouteCoordinate] {
        guard let value, value.utf8.count <= 50_000, let data = value.data(using: .utf8),
              let points = try? JSONDecoder().decode([RouteCoordinate].self, from: data),
              points.count >= 2, points.count <= 300,
              points.allSatisfy({ CLLocationCoordinate2DIsValid($0.coordinate) }) else { return [] }
        return points
    }
}

struct WorkoutRouteSharePreview: View {
    let coordinates: [RouteCoordinate]
    var body: some View {
        Map(interactionModes: []) {
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates.map(\.coordinate))
                    .stroke(ATHLTHTheme.accent, lineWidth: 5)
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Shared route preview")
    }
}
