import MapKit
import SwiftUI

struct SavedRoutesView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    let selectionTitle: String?
    let onSelect: ((TrainingRoute) -> Void)?

    @State private var watchMessage: String?
    @State private var watchError: String?

    init(
        selectionTitle: String? = nil,
        onSelect: ((TrainingRoute) -> Void)? = nil
    ) {
        self.selectionTitle = selectionTitle
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                routesHeader

                if session.savedRoutes.isEmpty {
                    emptyState
                } else {
                    ForEach(session.savedRoutes) { route in
                        routeCard(route)
                    }
                }
            }
            .padding()
            .padding(.bottom, 60)
        }
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(selectionTitle ?? "Routes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    RunRouteBuilderView()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create route")
            }
        }
        .alert(
            "ATHLTH",
            isPresented: Binding(
                get: { watchMessage != nil || watchError != nil },
                set: { presented in
                    if !presented {
                        watchMessage = nil
                        watchError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                watchMessage = nil
                watchError = nil
            }
        } message: {
            Text(watchError ?? watchMessage ?? "")
        }
    }

    private var routesHeader: some View {
        ATHLTHCard {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "map.fill")
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 14)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("My Routes")
                        .font(.title3.weight(.bold))

                    Text(
                        session.savedRoutes.isEmpty
                            ? "Create running routes directly in ATHLTH."
                            : "\(session.savedRoutes.count) saved route\(session.savedRoutes.count == 1 ? "" : "s")"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    RunRouteBuilderView()
                } label: {
                    Label("Create", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(ATHLTHTheme.accent)
            }
        }
    }

    private var emptyState: some View {
        ATHLTHCard {
            VStack(spacing: 14) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 70, height: 70)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Circle()
                    )

                Text("Create your first route")
                    .font(.title3.weight(.bold))

                Text(
                    "Choose a start and finish, compare route alternatives and save the route for future runs or Apple Watch."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                NavigationLink {
                    RunRouteBuilderView()
                } label: {
                    Label("Create Route", systemImage: "map.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(ATHLTHTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private func routeCard(_ route: TrainingRoute) -> some View {
        ATHLTHCard {
            if route.coordinates.count >= 2 {
                NavigationLink {
                    RouteDetailView(route: route)
                } label: {
                    Map(
                        initialPosition: .region(
                            region(for: route)
                        )
                    ) {
                        MapPolyline(
                            coordinates:
                                route.coordinates.map(\.coordinate)
                        )
                        .stroke(
                            ATHLTHTheme.accent,
                            lineWidth: 5
                        )

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
                    .allowsHitTesting(false)
                    .frame(height: 155)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Open \(route.title)"
                )
            }

            HStack(alignment: .top, spacing: 12) {
                NavigationLink {
                    RouteDetailView(route: route)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(route.title)
                                .font(.headline)
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )

                            if let start = route.startName,
                               let end = route.endName {
                                Text("\(start) → \(end)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            HStack(spacing: 10) {
                                Label(
                                    String(
                                        format: "%.1f km",
                                        route.distanceKilometers
                                    ),
                                    systemImage: "figure.run"
                                )

                                if let elevation =
                                    route.elevationGainMeters {
                                    Label(
                                        "\(Int(elevation.rounded())) m",
                                        systemImage: "mountain.2.fill"
                                    )
                                }

                                Label(
                                    visibilityLabel(
                                        route.visibility
                                    ),
                                    systemImage:
                                        visibilityIcon(
                                            route.visibility
                                        )
                                )
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .foregroundStyle(.tertiary)
                            .padding(.top, 3)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    if settings.trainingDeviceProvider == .appleWatch {
                        Button {
                            sendToWatch(route)
                        } label: {
                            Label(
                                "Send to Apple Watch",
                                systemImage: "applewatch"
                            )
                        }
                        .disabled(!watchConnection.isReady)
                    }

                    NavigationLink {
                        ChallengeCreationView(
                            preselectedRouteID: route.id
                        )
                    } label: {
                        Label(
                            "Create Challenge",
                            systemImage: "trophy.fill"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
            .padding(.top, 11)

            if let onSelect {
                Button {
                    onSelect(route)
                } label: {
                    Label(
                        "Use This Route",
                        systemImage: "checkmark.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accent)
            } else if settings.trainingDeviceProvider == .appleWatch {
                Button {
                    sendToWatch(route)
                } label: {
                    Label(
                        watchConnection.isReady
                            ? "Send to Apple Watch"
                            : "Apple Watch unavailable",
                        systemImage: "applewatch"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!watchConnection.isReady)
            }
        }
    }

    private func sendToWatch(_ route: TrainingRoute) {
        guard watchConnection.isReady else { return }

        do {
            try watchConnection.sendRoute(route)
            watchMessage = "Sent \(route.title) to Apple Watch."
        } catch {
            watchError = error.localizedDescription
        }
    }

    private func region(for route: TrainingRoute) -> MKCoordinateRegion {
        let coordinates = route.coordinates.map(\.coordinate)
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: 59.91,
                    longitude: 10.75
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: 0.08,
                    longitudeDelta: 0.08
                )
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
                latitudeDelta: max(
                    (maxLat - minLat) * 1.35,
                    0.01
                ),
                longitudeDelta: max(
                    (maxLong - minLong) * 1.35,
                    0.01
                )
            )
        )
    }

    private func visibilityLabel(
        _ visibility: ProfileVisibility
    ) -> String {
        switch visibility {
        case .privateOnly:
            return "Only me"
        case .friends:
            return "Friends"
        case .publicProfile:
            return "Public"
        }
    }

    private func visibilityIcon(
        _ visibility: ProfileVisibility
    ) -> String {
        switch visibility {
        case .privateOnly:
            return "lock.fill"
        case .friends:
            return "person.2.fill"
        case .publicProfile:
            return "globe.europe.africa.fill"
        }
    }
}
