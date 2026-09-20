import MapKit
import SwiftUI

struct WatchRouteDetailView: View {
    let route: WatchRouteTransfer

    private var coordinates: [CLLocationCoordinate2D] {
        route.points
            .sorted { $0.sequence < $1.sequence }
            .map {
                CLLocationCoordinate2D(
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                routeMap

                VStack(alignment: .leading, spacing: 3) {
                    Text(route.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Ready on Apple Watch")
                        .font(.system(size: 10))
                        .foregroundStyle(WatchTheme.muted)
                }

                HStack(spacing: 0) {
                    metric(
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        value: String(format: "%.1f km", route.distanceKilometers),
                        label: "Distance"
                    )

                    Divider()

                    if let elevation = route.elevationGainMeters {
                        metric(
                            icon: "mountain.2",
                            value: "\(Int(elevation.rounded())) m",
                            label: "Elevation"
                        )
                    } else {
                        metric(
                            icon: "mountain.2",
                            value: "—",
                            label: "Elevation"
                        )
                    }
                }
                .padding(.vertical, 8)
                .watchSurface(radius: 16)

                NavigationLink {
                    WatchWorkoutStartView(route: route)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                        Text("Start Route")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [
                            WatchTheme.green,
                            WatchTheme.deepGreen
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

                Text("Run or walk this route with live GPS, heart rate and distance.")
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .background(WatchTheme.canvas.ignoresSafeArea())
        .navigationTitle("Routes")
    }

    @ViewBuilder
    private var routeMap: some View {
        if coordinates.count >= 2 {
            Map {
                MapPolyline(coordinates: coordinates)
                    .stroke(WatchTheme.green, lineWidth: 4)
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(WatchTheme.border, lineWidth: 1)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundStyle(WatchTheme.green)

                Text("Route unavailable")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .watchSurface()
        }
    }

    @ViewBuilder
    private func metric(
        icon: String,
        value: String,
        label: String
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WatchTheme.green)

            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(WatchTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}
