import CoreGraphics
import CryptoKit
import Foundation

enum RouteMapSnapshotIdentity {
    /// Include every rendered point, owner and pixel scale. Endpoints alone
    /// cannot identify a route after its middle geometry has been edited.
    static func key(route: TrainingRoute, size: CGSize, scale: CGFloat) -> String {
        var digest = SHA256()
        for point in route.coordinates {
            digest.update(data: Data(
                "\(point.sequence):\(point.latitude.bitPattern):\(point.longitude.bitPattern);".utf8
            ))
        }
        let geometry = digest.finalize().map { String(format: "%02x", $0) }.joined()
        return [
            "route-thumbnail-v2", route.ownerID.uuidString, route.id.uuidString, geometry,
            String(Double(size.width).bitPattern), String(Double(size.height).bitPattern),
            String(Double(scale).bitPattern)
        ].joined(separator: "|")
    }
}
