import CoreGraphics
import CryptoKit
import Foundation

enum RouteMapSnapshotIdentity {
    /// Include every rendered point, owner and pixel scale. Endpoints alone
    /// cannot identify a route after its middle geometry has been edited.
    static func key(route: TrainingRoute, size: CGSize, scale: CGFloat) -> String {
        // One fixed-size buffer avoids allocating/interpolating text per GPS point.
        var coordinateBytes = Data(capacity: route.coordinates.count * 24)
        func append(_ value: UInt64) {
            var bigEndian = value.bigEndian
            withUnsafeBytes(of: &bigEndian) { coordinateBytes.append(contentsOf: $0) }
        }
        for point in route.coordinates {
            append(UInt64(bitPattern: Int64(point.sequence)))
            append(point.latitude.bitPattern)
            append(point.longitude.bitPattern)
        }
        let geometry = SHA256.hash(data: coordinateBytes)
            .map { String(format: "%02x", $0) }.joined()
        return [
            "route-thumbnail-v2", route.ownerID.uuidString, route.id.uuidString, geometry,
            String(Double(size.width).bitPattern), String(Double(size.height).bitPattern),
            String(Double(scale).bitPattern)
        ].joined(separator: "|")
    }
}
