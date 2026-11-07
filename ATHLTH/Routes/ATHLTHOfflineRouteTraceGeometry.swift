import CoreLocation
import Foundation

/// A guaranteed local preview of a saved route when no map tiles are
/// available. The input is *only* the locally stored route geometry.
enum ATHLTHOfflineRouteTraceGeometry {
    static func normalizedPoints(
        _ coordinates: [CLLocationCoordinate2D]
    ) -> [CGPoint] {
        let valid = coordinates.filter(CLLocationCoordinate2DIsValid)
        guard valid.count >= 2 else { return [] }

        // Scale longitudinal degrees by latitude so nearby north/south and
        // east/west movements are visually comparable at Norway's latitudes.
        let latitudes = valid.map(\.latitude)
        let centerLatitude = latitudes.reduce(0, +) / Double(valid.count)
        let longitudeFactor = max(
            0.01, abs(cos(centerLatitude * .pi / 180))
        )
        let xs = valid.map { $0.longitude * longitudeFactor }
        let ys = latitudes
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return [] }
        let spanX = maxX - minX
        let spanY = maxY - minY
        return xs.indices.map { index in
            CGPoint(
                x: spanX < 1e-10 ? 0.5 : (xs[index] - minX) / spanX,
                y: spanY < 1e-10 ? 0.5 : 1 - (ys[index] - minY) / spanY
            )
        }
    }
}
