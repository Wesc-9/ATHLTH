import MapKit
import SwiftUI
import UIKit

@MainActor
private enum RouteMapSnapshotCache {
    static let images =
        NSCache<NSString, UIImage>()

    static func image(
        for route: TrainingRoute,
        size: CGSize
    ) async -> UIImage? {
        let key =
            cacheKey(
                route: route,
                size: size
            ) as NSString

        if let cached =
            images.object(
                forKey: key
            ) {
            return cached
        }

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

            let rendered =
                drawRoute(
                    coordinates,
                    on: snapshot,
                    size: size
                )

            images.setObject(
                rendered,
                forKey: key,
                cost:
                    Int(
                        size.width *
                        size.height *
                        options.scale *
                        options.scale
                    )
            )

            return rendered
        } catch {
            return nil
        }
    }

    private static func cacheKey(
        route: TrainingRoute,
        size: CGSize
    ) -> String {
        let first =
            route.coordinates.first
        let last =
            route.coordinates.last

        return [
            route.id.uuidString,
            String(route.coordinates.count),
            String(
                format: "%.5f",
                first?.latitude ?? 0
            ),
            String(
                format: "%.5f",
                first?.longitude ?? 0
            ),
            String(
                format: "%.5f",
                last?.latitude ?? 0
            ),
            String(
                format: "%.5f",
                last?.longitude ?? 0
            ),
            String(Int(size.width)),
            String(Int(size.height))
        ]
        .joined(separator: "-")
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

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .fill(
                    ATHLTHTheme
                        .surfaceStone
                )

                if let image {
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
            .task(
                id: snapshotID(
                    width:
                        proxy.size.width
                )
            ) {
                guard image == nil,
                      proxy.size.width > 20
                else {
                    return
                }

                image =
                    await RouteMapSnapshotCache
                        .image(
                            for: route,
                            size:
                                CGSize(
                                    width:
                                        max(
                                            proxy
                                                .size
                                                .width,
                                            220
                                        ),
                                    height:
                                        height
                                )
                        )
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func snapshotID(
        width: CGFloat
    ) -> String {
        route.id.uuidString +
        "-" +
        String(route.coordinates.count) +
        "-" +
        String(Int(width))
    }
}
