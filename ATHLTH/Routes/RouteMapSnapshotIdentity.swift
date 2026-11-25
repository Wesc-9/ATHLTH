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


/// View-local identity memo: do not allocate a GPS buffer and hash every
/// point again merely because a parent view or geometry reader redraws.
final class RouteMapSnapshotIdentityMemo {
    private struct Key: Equatable {
        let account: UUID
        let owner: UUID
        let route: UUID
        let coordinates: [RouteCoordinate]
        let size: CGSize
        let scale: CGFloat
    }
    private let memo = ATHLTHProjectionMemo<Key, String>()

    func key(route: TrainingRoute, size: CGSize, scale: CGFloat, account: UUID) -> String {
        let input = Key(account: account, owner: route.ownerID, route: route.id,
                        coordinates: route.coordinates, size: size, scale: scale)
        return memo.value(for: input) {
            let signpost = ATHLTHPerformance.begin("RouteThumbnailIdentity")
            defer { ATHLTHPerformance.end("RouteThumbnailIdentity", id: signpost) }
            return RouteMapSnapshotIdentity.key(route: route, size: size, scale: scale)
                + "|" + account.uuidString
        }
    }
}
