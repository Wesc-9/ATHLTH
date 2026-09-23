import MapKit
import SwiftUI

struct SavedRoutesView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var challengeStore: ChallengeStore

    @State private var watchMessage: String?
    @State private var watchError: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if session.savedRoutes.isEmpty {
                    ContentUnavailableView(
                        "No saved routes",
                        systemImage: "map",
                        description: Text("Create an A-to-B route or import a GPX file from Train.")
                    )
                    .padding(.vertical, 60)
                } else {
                    ForEach(session.savedRoutes) { route in
                        routeCard(route)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Saved Routes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    RunRouteBuilderView()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("ATHLTH", isPresented: Binding(
            get: { watchMessage != nil || watchError != nil },
            set: { presented in
                if !presented {
                    watchMessage = nil
                    watchError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                watchMessage = nil
                watchError = nil
            }
        } message: {
            Text(watchError ?? watchMessage ?? "")
        }
    }

    private func routeCard(_ route: TrainingRoute) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if route.coordinates.count >= 2 {
                Map(initialPosition: .region(region(for: route))) {
                    MapPolyline(coordinates: route.coordinates.map(\.coordinate))
                        .stroke(ATHLTHTheme.accent, lineWidth: 5)

                    if let first = route.coordinates.first {
                        Marker(
                            route.startName ?? "Start",
                            coordinate: first.coordinate
                        )
                        .tint(ATHLTHTheme.accent)
                    }

                    if let last = route.coordinates.last {
                        Marker(
                            route.endName ?? "Finish",
                            coordinate: last.coordinate
                        )
                        .tint(.red)
                    }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.title)
                        .font(.headline)

                    HStack(spacing: 6) {
                        Label(
                            String(format: "%.2f km", route.distanceKilometers),
                            systemImage: "figure.run"
                        )

                        Text("·")

                        Label(
                            route.visibility.title,
                            systemImage: visibilityIcon(route.visibility)
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let start = route.startName,
                       let end = route.endName {
                        Text("\(start) → \(end)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Menu {
                    if settings.trainingDeviceProvider == .appleWatch {
                        Button {
                            guard watchConnection.isReady else { return }
                            do {
                                try watchConnection.sendRoute(route)
                                watchMessage = "Sent \(route.title) to Apple Watch."
                            } catch {
                                watchError = error.localizedDescription
                            }
                        } label: {
                            Label("Send to Apple Watch", systemImage: "applewatch")
                        }
                        .disabled(!watchConnection.isReady)
                    } else if settings.trainingDeviceProvider == .garmin {
                        Button {} label: {
                            Label(
                                "Garmin route sync · Planned",
                                systemImage: "watch.analog"
                            )
                        }
                        .disabled(true)
                    }

                    NavigationLink {
                        ChallengeCreationView(preselectedRouteID: route.id)
                    } label: {
                        Label("Create Challenge", systemImage: "trophy.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }

            if route.visibility == .publicProfile {
                Label(
                    "Public route · ready for public discovery in the upcoming route map",
                    systemImage: "globe.europe.africa.fill"
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.accent)
            }
        }
        .padding(14)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func region(for route: TrainingRoute) -> MKCoordinateRegion {
        let coordinates = route.coordinates.map(\.coordinate)
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 59.91, longitude: 10.75),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }

        let lats = coordinates.map(\.latitude)
        let longs = coordinates.map(\.longitude)

        let minLat = lats.min() ?? coordinates[0].latitude
        let maxLat = lats.max() ?? coordinates[0].latitude
        let minLong = longs.min() ?? coordinates[0].longitude
        let maxLong = longs.max() ?? coordinates[0].longitude

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLong + maxLong) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.35, 0.01),
                longitudeDelta: max((maxLong - minLong) * 1.35, 0.01)
            )
        )
    }

    private func visibilityIcon(_ visibility: ProfileVisibility) -> String {
        switch visibility {
        case .privateOnly: return "lock.fill"
        case .friends: return "person.2.fill"
        case .publicProfile: return "globe.europe.africa.fill"
        }
    }
}
