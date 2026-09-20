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

                Text(route.title)
                    .font(.headline)

                HStack {
                    Label(
                        String(format: "%.1f km", route.distanceKilometers),
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )

                    if let elevation = route.elevationGainMeters {
                        Spacer()
                        Label(
                            "\(Int(elevation.rounded())) m",
                            systemImage: "mountain.2"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Start workout") {}
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(true)

                Text("Workout recording is the next Watch milestone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Route")
    }

    @ViewBuilder
    private var routeMap: some View {
        if coordinates.count >= 2 {
            Map {
                MapPolyline(coordinates: coordinates)
                    .stroke(.green, lineWidth: 4)
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            ContentUnavailableView(
                "Route unavailable",
                systemImage: "map"
            )
            .frame(height: 100)
        }
    }
}
