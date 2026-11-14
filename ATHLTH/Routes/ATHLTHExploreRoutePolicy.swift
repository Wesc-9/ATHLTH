import CoreLocation
import Foundation
import MapKit

/// Display-only geometry. Never replace the GPS route used for navigation,
/// training evidence or saved routes with a simplified preview.
enum ATHLTHExploreRoutePolicy {
    static func isLoop(_ points: [CLLocationCoordinate2D]) -> Bool {
        guard let first = points.first, let last = points.last,
              CLLocationCoordinate2DIsValid(first),
              CLLocationCoordinate2DIsValid(last) else { return false }
        return CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: last.latitude,
                                       longitude: last.longitude)) < 35
    }

    /// Ramer-Douglas-Peucker with a fixed point budget: unlike a fixed stride,
    /// keeps sharp turns and switchbacks even when the data is very dense.
    static func displayPoints(
        _ points: [CLLocationCoordinate2D],
        maximum: Int
    ) -> [CLLocationCoordinate2D] {
        let valid = points.filter(CLLocationCoordinate2DIsValid)
        let budget = max(2, maximum)
        guard valid.count > budget else { return valid }

        let midLatitude = valid[valid.count / 2].latitude * .pi / 180
        let xScale = 111_320 * max(0.01, abs(cos(midLatitude)))
        let yScale = 111_132.0
        let planar = valid.map { (x: $0.longitude * xScale, y: $0.latitude * yScale) }

        func reduced(_ squaredTolerance: Double) -> [Int] {
            var kept = [Bool](repeating: false, count: valid.count)
            kept[0] = true
            kept[valid.count - 1] = true
            var stack: [(Int, Int)] = [(0, valid.count - 1)]

            while let (start, end) = stack.popLast() {
                guard end > start + 1 else { continue }
                let a = planar[start]
                let b = planar[end]
                let dx = b.x - a.x
                let dy = b.y - a.y
                let denominator = dx * dx + dy * dy
                var maxSquared = squaredTolerance
                var best: Int?

                for index in (start + 1)..<end {
                    let candidate = planar[index]
                    let t = denominator > 0
                        ? min(1, max(0, ((candidate.x - a.x) * dx +
                                             (candidate.y - a.y) * dy) / denominator))
                        : 0
                    let deltaX = candidate.x - (a.x + t * dx)
                    let deltaY = candidate.y - (a.y + t * dy)
                    let distance = deltaX * deltaX + deltaY * deltaY
                    if distance > maxSquared {
                        maxSquared = distance
                        best = index
                    }
                }

                if let best {
                    kept[best] = true
                    stack.append((start, best))
                    stack.append((best, end))
                }
            }
            return kept.indices.filter { kept[$0] }
        }

        let xs = planar.map(\.x)
        let ys = planar.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return [] }
        var lower = 0.0
        var upper = hypot(maxX - minX, maxY - minY) + 1
        var best = [0, valid.count - 1]

        for _ in 0..<13 {
            let middle = (lower + upper) / 2
            let indices = reduced(middle * middle)
            if indices.count > budget {
                lower = middle
            } else {
                best = indices
                upper = middle
            }
        }
        return best.map { valid[$0] }
    }

    /// This copy is used only when starting a workout in the opposite direction.
    /// The underlying saved/public route and its identity remain unchanged.
    static func reversedForWorkout(_ route: TrainingRoute) -> TrainingRoute {
        var result = route
        result.coordinates = route.coordinates.reversed().enumerated().map {
            var point = $0.element
            point.sequence = $0.offset
            return point
        }
        result.startName = route.endName
        result.endName = route.startName
        return result
    }

    struct Center: Hashable {
        let id: UUID
        let latitude: Double
        let longitude: Double
    }

    struct Cluster: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let routeIDs: [UUID]
        var count: Int { routeIDs.count }
    }

    /// At broad zoom, replace dozens of overlapping pins/polylines with
    /// stable geographic buckets. Clustering never discards any route data.
    static func clusters(
        _ centers: [Center],
        region: MKCoordinateRegion
    ) -> [Cluster] {
        guard region.span.latitudeDelta.isFinite,
              region.span.longitudeDelta.isFinite else { return [] }
        let latitudeCell = max(0.015, region.span.latitudeDelta / 6)
        let longitudeCell = max(0.015, region.span.longitudeDelta / 6)

        var buckets: [String: [Center]] = [:]
        for item in centers where item.latitude.isFinite && item.longitude.isFinite &&
            abs(item.latitude) <= 90 && abs(item.longitude) <= 180 {
            let y = Int(floor(item.latitude / latitudeCell))
            let x = Int(floor(item.longitude / longitudeCell))
            buckets["\(x):\(y)", default: []].append(item)
        }

        return buckets.map { key, members in
            Cluster(
                id: key,
                coordinate: CLLocationCoordinate2D(
                    latitude: members.reduce(0) { $0 + $1.latitude } /
                        Double(members.count),
                    longitude: members.reduce(0) { $0 + $1.longitude } /
                        Double(members.count)
                ),
                routeIDs: members.map(\.id)
            )
        }
        .sorted { $0.id < $1.id }
    }
}
