import MapKit
import SwiftUI
import UIKit

/// Shared, geometry-only route direction hints for maps and map thumbnails.
/// A closed loop is NOT assumed to be an out-and-back: the return path must
/// substantially overlap the outbound path before a turnaround is shown.
enum ATHLTHRouteDirectionGeometry {
    struct Arrow: Identifiable {
        let id: Int
        let coordinate: CLLocationCoordinate2D
        let bearingDegrees: Double
        let returning: Bool
    }

    static func turnaroundIndex(
        _ coordinates: [CLLocationCoordinate2D]
    ) -> Int? {
        guard coordinates.count >= 6 else { return nil }
        let locations = coordinates.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        guard let first = locations.first, let last = locations.last,
              first.distance(from: last) <= 110 else { return nil }
        var pathLength = 0.0
        for i in 1..<locations.count {
            pathLength += locations[i].distance(from: locations[i - 1])
        }
        guard pathLength >= 450 else { return nil }
        guard let farthest = locations.indices.max(by: {
            first.distance(from: locations[$0]) <
            first.distance(from: locations[$1])
        }), farthest > 2, farthest < locations.count - 3 else { return nil }
        let farDistance = first.distance(from: locations[farthest])
        guard farDistance >= 160 else { return nil }

        // Compare a small number of outbound samples against the reverse
        // leg, not against the entire path. Crossings in a loop do not count.
        let strideOut = max(1, farthest / 12)
        let strideReturn = max(1, (locations.count - farthest) / 180)
        let samples = Array(stride(from: 1, through: farthest - 1, by: strideOut))
        guard samples.count >= 3 else { return nil }
        let overlaps = samples.filter { outboundIndex in
            stride(from: farthest + 1, through: locations.count - 1,
                   by: strideReturn).contains { returnIndex in
                locations[outboundIndex].distance(from: locations[returnIndex]) <= 40
            }
        }
        return Double(overlaps.count) / Double(samples.count) >= 0.6
            ? farthest : nil
    }

    static func arrows(
        for coordinates: [CLLocationCoordinate2D]
    ) -> [Arrow] {
        guard coordinates.count >= 3 else { return [] }
        let turn = turnaroundIndex(coordinates)
        let indices: [(Int, Bool)] = {
            if let turn {
                // Space the markers along different legs so two overlapping
                // road geometries are still readable on a small preview.
                return [
                    (max(1, turn / 4), false),
                    (min(coordinates.count - 2,
                         turn + max(1, (coordinates.count - turn) / 3)), true)
                ]
            }
            return [(max(1, coordinates.count / 3), false),
                    (min(coordinates.count - 2, coordinates.count * 2 / 3), false)]
        }()
        return indices.enumerated().map { index, entry in
            let position = entry.0
            let from = coordinates[position]
            let to = coordinates[min(position + 1, coordinates.count - 1)]
            let fromLat = from.latitude * .pi / 180
            let toLat = to.latitude * .pi / 180
            let delta = (to.longitude - from.longitude) * .pi / 180
            let y = sin(delta) * cos(toLat)
            let x = cos(fromLat) * sin(toLat) -
                sin(fromLat) * cos(toLat) * cos(delta)
            return Arrow(
                id: index,
                coordinate: from,
                bearingDegrees: atan2(y, x) * 180 / .pi,
                returning: entry.1
            )
        }
    }
}

@MainActor
enum RouteMapSnapshotCache {
    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 12
        cache.totalCostLimit = 12 * 1_024 * 1_024
        return cache
    }()

    private static var generation: UInt64 = 0

    static func clearCache() {
        generation &+= 1
        images.removeAllObjects()
    }

    static func image(
        for route: TrainingRoute,
        size: CGSize,
        requestID: String
    ) async -> UIImage? {
        let key = requestID as NSString

        if let cached =
            images.object(
                forKey: key
            ) {
            return cached
        }

        let requestedGeneration = generation
        let coordinates =
            route.coordinates
                .sorted {
                    $0.sequence <
                    $1.sequence
                }
                .map(\.coordinate)

        guard coordinates.count >= 2
        else {
            return nil
        }

        let options =
            MKMapSnapshotter.Options()
        options.region =
            region(
                for: coordinates
            )
        options.size = size
        options.scale =
            UIScreen.main.scale
        options.mapType = .standard
        options.showsBuildings = false
        options.pointOfInterestFilter =
            .excludingAll

        do {
            let snapshot =
                try await MKMapSnapshotter(
                    options: options
                )
                .start()

            guard !Task.isCancelled else { return nil }
            let rendered =
                drawRoute(
                    coordinates,
                    on: snapshot,
                    size: size
                )

            if requestedGeneration == generation {
                images.setObject(
                    rendered,
                    forKey: key,
                    cost: rendered.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
                )
            }

            return rendered
        } catch {
            return nil
        }
    }

    static func image(
        for coordinates: [CLLocationCoordinate2D],
        size: CGSize,
        requestID: String
    ) async -> UIImage? {
        let key = requestID as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard coordinates.count >= 2 else { return nil }
        let currentGeneration = generation
        let options = MKMapSnapshotter.Options()
        options.region = region(for: coordinates)
        options.size = size
        options.scale = UIScreen.main.scale
        options.mapType = .standard
        options.showsBuildings = false
        options.pointOfInterestFilter = .excludingAll
        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            guard !Task.isCancelled else { return nil }
            let rendered = drawRoute(coordinates, on: snapshot, size: size)
            if currentGeneration == generation {
                images.setObject(rendered, forKey: key)
            }
            return rendered
        } catch { return nil }
    }

    private static func region(
        for coordinates:
            [CLLocationCoordinate2D]
    ) -> MKCoordinateRegion {
        let latitudes =
            coordinates.map(\.latitude)
        let longitudes =
            coordinates.map(\.longitude)

        guard let minLatitude =
                latitudes.min(),
              let maxLatitude =
                latitudes.max(),
              let minLongitude =
                longitudes.min(),
              let maxLongitude =
                longitudes.max()
        else {
            return MKCoordinateRegion(
                center:
                    coordinates[0],
                span:
                    MKCoordinateSpan(
                        latitudeDelta: 0.02,
                        longitudeDelta: 0.02
                    )
            )
        }

        let center =
            CLLocationCoordinate2D(
                latitude:
                    (
                        minLatitude +
                        maxLatitude
                    ) / 2,
                longitude:
                    (
                        minLongitude +
                        maxLongitude
                    ) / 2
            )

        return MKCoordinateRegion(
            center: center,
            span:
                MKCoordinateSpan(
                    latitudeDelta:
                        max(
                            (
                                maxLatitude -
                                minLatitude
                            ) * 1.32,
                            0.0045
                        ),
                    longitudeDelta:
                        max(
                            (
                                maxLongitude -
                                minLongitude
                            ) * 1.32,
                            0.0045
                        )
                )
        )
    }

    private static func drawRoute(
        _ coordinates:
            [CLLocationCoordinate2D],
        on snapshot:
            MKMapSnapshotter.Snapshot,
        size: CGSize
    ) -> UIImage {
        let format =
            UIGraphicsImageRendererFormat()
        format.scale =
            UIScreen.main.scale
        format.opaque = true

        return UIGraphicsImageRenderer(
            size: size,
            format: format
        )
        .image { renderer in
            snapshot.image.draw(
                in:
                    CGRect(
                        origin: .zero,
                        size: size
                    )
            )

            let points =
                coordinates.map {
                    snapshot.point(
                        for: $0
                    )
                }

            guard points.count >= 2
            else {
                return
            }

            let path =
                UIBezierPath()
            path.move(
                to: points[0]
            )
            for point in
                points.dropFirst() {
                path.addLine(
                    to: point
                )
            }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            let context =
                renderer.cgContext

            context.saveGState()
            context.setLineCap(.round)
            context.setLineJoin(.round)

            context.addPath(
                path.cgPath
            )
            context.setStrokeColor(
                UIColor.white
                    .withAlphaComponent(0.92)
                    .cgColor
            )
            context.setLineWidth(7)
            context.strokePath()

            context.addPath(
                path.cgPath
            )
            context.setStrokeColor(
                UIColor(
                    ATHLTHTheme.vitality
                ).cgColor
            )
            context.setLineWidth(4)
            context.strokePath()

            let turn = ATHLTHRouteDirectionGeometry.turnaroundIndex(coordinates)
            for arrow in ATHLTHRouteDirectionGeometry.arrows(for: coordinates) {
                let location = snapshot.point(for: arrow.coordinate)
                guard location.x.isFinite, location.y.isFinite else { continue }
                context.saveGState()
                context.translateBy(x: location.x, y: location.y)
                context.rotate(by: CGFloat(arrow.bearingDegrees * .pi / 180))
                context.setFillColor(UIColor.white.cgColor)
                context.fillEllipse(in: CGRect(x: -10, y: -10, width: 20, height: 20))
                context.setFillColor(UIColor(
                    arrow.returning ? ATHLTHTheme.accentDeep :
                        ATHLTHTheme.premiumGold
                ).cgColor)
                context.move(to: CGPoint(x: 0, y: -7))
                context.addLine(to: CGPoint(x: -5.5, y: 6))
                context.addLine(to: CGPoint(x: 0, y: 3))
                context.addLine(to: CGPoint(x: 5.5, y: 6))
                context.closePath()
                context.fillPath()
                context.restoreGState()
            }
            if let turn {
                drawMarker(
                    at: points[turn],
                    fill: UIColor(ATHLTHTheme.premiumGold),
                    context: context
                )
            }

            if let start =
                    points.first,
               let finish =
                    points.last {
                drawMarker(
                    at: start,
                    fill:
                        UIColor(
                            ATHLTHTheme
                                .accentDeep
                        ),
                    context: context
                )
                drawMarker(
                    at: finish,
                    fill:
                        UIColor(
                            ATHLTHTheme
                                .vitality
                        ),
                    context: context
                )
            }

            context.restoreGState()
        }
    }

    private static func drawMarker(
        at point: CGPoint,
        fill: UIColor,
        context: CGContext
    ) {
        let outer =
            CGRect(
                x: point.x - 6,
                y: point.y - 6,
                width: 12,
                height: 12
            )
        context.setFillColor(
            UIColor.white.cgColor
        )
        context.fillEllipse(
            in: outer
        )

        let inner =
            outer.insetBy(
                dx: 2.5,
                dy: 2.5
            )
        context.setFillColor(
            fill.cgColor
        )
        context.fillEllipse(
            in: inner
        )
    }
}

struct RouteMapSnapshotThumbnail: View {
    @EnvironmentObject private var session: AppSessionStore
    let route: TrainingRoute
    var height: CGFloat = 118

    @State private var image:
        UIImage?
    @State private var imageRequestID: String?

    private var offlineTrace: some View {
        let coordinates = route.coordinates
            .sorted { $0.sequence < $1.sequence }
            .map(\.coordinate)
        let points = ATHLTHOfflineRouteTraceGeometry.normalizedPoints(coordinates)
        return ZStack(alignment: .bottomLeading) {
            ATHLTHPlanDesign.selectedSurface
            if points.count >= 2 {
                Canvas { context, size in
                    let inset: CGFloat = 20
                    let availableWidth = max(1, size.width - inset * 2)
                    let availableHeight = max(1, size.height - inset * 2)
                    let pathPoints = points.map { point in
                        CGPoint(
                            x: inset + point.x * availableWidth,
                            y: inset + point.y * availableHeight
                        )
                    }
                    var path = Path()
                    path.addLines(pathPoints)
                    context.stroke(
                        path, with: .color(.white),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round,
                                           lineJoin: .round)
                    )
                    context.stroke(
                        path, with: .color(ATHLTHPlanDesign.accentInk),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round,
                                           lineJoin: .round)
                    )
                    if let start = pathPoints.first,
                       let finish = pathPoints.last {
                        for (point, tint) in [
                            (start, ATHLTHPlanDesign.ink),
                            (finish, ATHLTHTheme.vitality)
                        ] {
                            context.fill(
                                Path(ellipseIn: CGRect(
                                    x: point.x - 5, y: point.y - 5,
                                    width: 10, height: 10
                                )),
                                with: .color(tint)
                            )
                        }
                    }
                }
            } else {
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Label(
                ATHLTHLocalization.choose(
                    english: "Route preview · offline",
                    norwegian: "Rutevisning · uten nett"
                ),
                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(ATHLTHPlanDesign.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .padding(9)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: max(proxy.size.width, 88), height: height)
            let requestID = RouteMapSnapshotIdentity.key(
                route: route, size: size, scale: UIScreen.main.scale
            )
            ZStack {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .fill(
                    ATHLTHTheme
                        .surfaceStone
                )

                if imageRequestID == requestID, let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Never show an endless spinner with airplane mode on.
                    // Coordinates are already in the saved route, so the
                    // track can be drawn immediately without map tiles.
                    offlineTrace
                }
            }
            .frame(
                width:
                    proxy.size.width,
                height: height
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    Color.white
                        .opacity(0.75),
                    lineWidth: 0.8
                )
            }
            .task(id: requestID) {
                guard proxy.size.width > 20 else { return }
                // Show any previously downloaded snapshot immediately.
                // A new MapKit request may fail, particularly in flight mode.
                if let prepared = AthleteOfflinePackStore.cachedRouteSnapshot(
                    routeID: route.id, userID: session.profile.userID
                ) {
                    image = prepared
                    imageRequestID = requestID
                }
                let loaded = await RouteMapSnapshotCache.image(
                    for: route, size: size, requestID: requestID
                )
                guard !Task.isCancelled else { return }
                if let loaded {
                    image = loaded
                }
                // When neither image is available, show the local route
                // trace rather than a blank tile or an endless spinner.
                imageRequestID = requestID
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

}

struct GhostReplayRouteThumbnail: View {
    @EnvironmentObject private var health: HealthKitManager
    let workoutID: UUID
    let ownerID: UUID
    var height: CGFloat = 86

    @State private var image: UIImage?
    @State private var resolvedID: String?
    @State private var loading = true

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let size = CGSize(width: max(width, 1), height: height)
            let key = [
                "replay-map-v1", ownerID.uuidString, workoutID.uuidString,
                String(Int(width.rounded())), String(Int(height.rounded()))
            ].joined(separator: "|")
            ZStack {
                ATHLTHTheme.surfaceStone
                if resolvedID == key, let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "map")
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .task(id: key) {
                guard width > 20 else { return }
                image = nil
                resolvedID = nil
                loading = true
                let locations = await health.workoutRoute(for: workoutID)
                guard !Task.isCancelled else { return }
                let result = await RouteMapSnapshotCache.image(
                    for: locations.map(\.coordinate),
                    size: size,
                    requestID: key
                )
                guard !Task.isCancelled else { return }
                image = result
                resolvedID = key
                loading = false
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
