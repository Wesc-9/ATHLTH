import MapKit
import SwiftUI
import UIKit

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
    let route: TrainingRoute
    var height: CGFloat = 118

    @State private var image:
        UIImage?
    @State private var imageRequestID: String?

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: max(proxy.size.width, 220), height: height)
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
                    Image(
                        uiImage: image
                    )
                    .resizable()
                    .scaledToFill()
                } else {
                    VStack(spacing: 6) {
                        Image(
                            systemName:
                                "map.fill"
                        )
                        .font(.title3)
                        .foregroundStyle(
                            ATHLTHTheme
                                .vitality
                        )

                        ProgressView()
                            .controlSize(
                                .mini
                            )
                    }
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
                let loaded = await RouteMapSnapshotCache.image(
                    for: route, size: size, requestID: requestID
                )
                guard !Task.isCancelled else { return }
                image = loaded
                imageRequestID = requestID
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

}
