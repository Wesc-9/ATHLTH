import CoreLocation
import MapKit
import SwiftUI
import Charts

/// iPad-first route inspection, keeping saved routes in AppSessionStore.
/// Editing delegates to the existing MapKit route builder so there is only
/// one route creation and persistence engine on all Apple devices.
struct ATHLTHStudioRouteWorkspaceView: View {
    @EnvironmentObject private var session: AppSessionStore
    @State private var selectedID: UUID?
    @State private var query = ""
    @State private var showingRouteBuilder = false
    @State private var showingRouteDetails = false
    @State private var showingExplore = false
    @State private var targetPaceSeconds = 300.0

    private var routes: [TrainingRoute] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return session.savedRoutes.filter {
            text.isEmpty ||
            $0.title.localizedCaseInsensitiveContains(text) ||
            ($0.startName?.localizedCaseInsensitiveContains(text) == true) ||
            ($0.endName?.localizedCaseInsensitiveContains(text) == true)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private var selected: TrainingRoute? {
        session.savedRoutes.first(where: { $0.id == selectedID })
            ?? routes.first
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 860
            Group {
                if wide {
                    HStack(spacing: 0) {
                        routeList
                            .frame(width: min(max(260, geo.size.width * 0.29), 355))
                        Rectangle()
                            .fill(ATHLTHStudioStyle.outline.opacity(0.7))
                            .frame(width: 1)
                        preview
                    }
                } else {
                    VStack(spacing: 0) {
                        routeList
                            .frame(height: min(240, geo.size.height * 0.34))
                        Divider()
                        preview
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ATHLTHStudioStyle.canvas.ignoresSafeArea())
        .sheet(isPresented: $showingRouteBuilder) {
            RunRouteBuilderView(onRouteSaved: {
                selectedID = session.savedRoutes.max {
                    $0.createdAt < $1.createdAt
                }?.id
            })
        }
        .sheet(isPresented: $showingRouteDetails) {
            if let selected {
                RouteDetailView(route: selected)
            }
        }
        .sheet(isPresented: $showingExplore) {
            NavigationStack {
                ATHLTHExploreView()
            }
        }
        .onChange(of: session.profile.userID) { _, _ in
            selectedID = nil
            query = ""
        }
        .accessibilityIdentifier("athlth-ipad-route-studio")
    }

    private var routeList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ROUTE STUDIO")
                        .font(.caption2.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ATHLTHStudioStyle.gold)
                    Text(tr("Your routes", "Dine ruter"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                }
                Spacer(minLength: 0)
                Button {
                    showingRouteBuilder = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHStudioStyle.ink)
                .accessibilityLabel(tr("Create route", "Opprett rute"))
            }
            TextField(tr("Find saved route", "Søk i lagrede ruter"), text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("athlth-ipad-route-search")

            if routes.isEmpty {
                ContentUnavailableView(
                    tr("No matching routes", "Ingen ruter funnet"),
                    systemImage: "map",
                    description: Text(tr(
                        "Create a route or change the search.",
                        "Opprett en rute eller endre søket."
                    ))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(routes) { route in
                            Button {
                                selectedID = route.id
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                        .font(.system(size: 18))
                                        .foregroundStyle(ATHLTHStudioStyle.gold)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(route.title)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(2)
                                        Text(String(format: "%.1f km", route.distanceKilometers))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 5)
                                    if selected?.id == route.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(ATHLTHStudioStyle.gold)
                                    }
                                }
                                .foregroundStyle(ATHLTHStudioStyle.ink)
                                .padding(13)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    selected?.id == route.id
                                        ? Color.white : ATHLTHStudioStyle.canvas,
                                    in: RoundedRectangle(cornerRadius: 13)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13)
                                        .stroke(selected?.id == route.id
                                            ? ATHLTHStudioStyle.gold.opacity(0.65)
                                            : ATHLTHStudioStyle.outline.opacity(0.35))
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(
                                selected?.id == route.id ? .isSelected : []
                            )
                        }
                    }
                }
            }
            Button {
                showingExplore = true
            } label: {
                Label(tr("Explore nearby routes", "Utforsk ruter"),
                      systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(ATHLTHStudioStyle.paper)
    }

    @ViewBuilder
    private var preview: some View {
        if let route = selected {
            GeometryReader { geo in
                let narrow = geo.size.width < 700
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(route.title)
                                    .font(.system(size: narrow ? 22 : 29,
                                                  weight: .semibold, design: .rounded))
                                    .foregroundStyle(ATHLTHStudioStyle.ink)
                                Text([route.startName, route.endName]
                                    .compactMap { $0 }.joined(separator: " – "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                showingRouteDetails = true
                            } label: {
                                Label(tr("Route details", "Rutedetaljer"),
                                      systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.bordered)
                        }
                        routeMap(route)
                            .frame(height: narrow ? 235 : 320)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .accessibilityIdentifier("athlth-ipad-route-preview")

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { routeMetrics(route) }
                            VStack(spacing: 9) { routeMetrics(route) }
                        }

                        ghostTargetPreview(route)
                        elevationPreview(route)

                        Text(tr(
                            "Route previews and target times are estimates. Current GPS tracking remains on iPhone or Apple Watch.",
                            "Rutevisning og måltider er estimater. GPS-opptaket gjøres fortsatt på iPhone eller Apple Watch."
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(narrow ? 14 : 23)
                    .frame(maxWidth: 1050)
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            ContentUnavailableView(
                tr("Select a route", "Velg en rute"),
                systemImage: "map",
                description: Text(tr(
                    "Your saved routes will appear here.",
                    "Lagrede ruter vises her."
                ))
            )
        }
    }

    @ViewBuilder
    private func routeMetrics(_ route: TrainingRoute) -> some View {
        ATHLTHStudioMetricCard(
            title: tr("Distance", "Distanse"),
            value: String(format: "%.2f km", route.distanceKilometers),
            note: tr("Saved route", "Lagret rute")
        )
        ATHLTHStudioMetricCard(
            title: tr("Climbing", "Stigning"),
            value: route.elevationGainMeters.map {
                String(format: "%.0f m", $0)
            } ?? "—",
            note: tr("When available", "Når tilgjengelig")
        )
        ATHLTHStudioMetricCard(
            title: tr("Waypoints", "Rutepunkter"),
            value: "\(route.coordinates.count)",
            note: tr("Recorded geometry", "Registrert geometri")
        )
    }

    private func routeMap(_ route: TrainingRoute) -> some View {
        let points = route.coordinates.sorted {
            $0.sequence < $1.sequence
        }.map(\.coordinate)
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        let region: MKCoordinateRegion = {
            guard let first = points.first else {
                return MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 63.43, longitude: 10.4),
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            }
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: ((latitudes.min() ?? first.latitude) +
                               (latitudes.max() ?? first.latitude)) / 2,
                    longitude: ((longitudes.min() ?? first.longitude) +
                                (longitudes.max() ?? first.longitude)) / 2
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: max(0.008,
                        ((latitudes.max() ?? first.latitude) -
                         (latitudes.min() ?? first.latitude)) * 1.5),
                    longitudeDelta: max(0.008,
                        ((longitudes.max() ?? first.longitude) -
                         (longitudes.min() ?? first.longitude)) * 1.5)
                )
            )
        }()

        return Map(initialPosition: .region(region)) {
            if points.count >= 2 {
                MapPolyline(coordinates: points)
                    .stroke(ATHLTHStudioStyle.gold,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            if let first = points.first {
                Annotation("Start", coordinate: first) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.title2)
                        .foregroundStyle(ATHLTHStudioStyle.gold)
                        .background(.white, in: Circle())
                }
            }
            if let last = points.last {
                Annotation("Finish", coordinate: last) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(.title2)
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                        .background(.white, in: Circle())
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }

    private func ghostTargetPreview(_ route: TrainingRoute) -> some View {
        let km = GhostTargetRouteEligibility.geometryDistanceKilometers(route)
        let estimate = km.map { $0 * targetPaceSeconds }
        return VStack(alignment: .leading, spacing: 13) {
            Label(tr("GHOST RACE TARGET PREVIEW", "GHOST RACE – MÅL"),
                  systemImage: "figure.run.circle")
                .font(.caption.weight(.semibold))
                .tracking(0.9)
                .foregroundStyle(ATHLTHStudioStyle.gold)
            HStack(spacing: 12) {
                Text(tr("Target pace", "Måltempo"))
                    .font(.subheadline)
                Spacer()
                Picker(tr("Target pace", "Måltempo"), selection: $targetPaceSeconds) {
                    Text("4:00 /km").tag(240.0)
                    Text("4:30 /km").tag(270.0)
                    Text("5:00 /km").tag(300.0)
                    Text("5:30 /km").tag(330.0)
                    Text("6:00 /km").tag(360.0)
                    Text("6:30 /km").tag(390.0)
                }
                .pickerStyle(.menu)
            }
            HStack {
                Text(tr("Projected time", "Beregnet sluttid"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(estimate.map { seconds in
                    let total = Int(seconds.rounded())
                    return String(format: "%d:%02d:%02d",
                                  total / 3600, (total % 3600) / 60,
                                  total % 60)
                } ?? "—")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(ATHLTHStudioStyle.ink)
            }
            if km == nil {
                Text(tr(
                    "This route needs at least 200 m of valid GPS geometry for Ghost Race.",
                    "Ruten trenger minst 200 m gyldig GPS-geometri for Ghost Race."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private func elevationPreview(_ route: TrainingRoute) -> some View {
        let ordered = route.coordinates.sorted { $0.sequence < $1.sequence }
        let allHaveElevation = ordered.count >= 2 &&
            ordered.allSatisfy { $0.altitude?.isFinite == true }
        let elevations = allHaveElevation
            ? ordered.enumerated().compactMap { index, point -> ElevationPoint? in
                guard let altitude = point.altitude else { return nil }
                return ElevationPoint(index: index, meters: altitude)
            }
            : []
        return VStack(alignment: .leading, spacing: 10) {
            Label(tr("ELEVATION PROFILE", "HØYDEPROFIL"),
                  systemImage: "mountain.2")
                .font(.caption.weight(.semibold))
                .tracking(0.9)
                .foregroundStyle(ATHLTHStudioStyle.gold)
            if elevations.count >= 2 {
                Chart(elevations) { point in
                    LineMark(x: .value("Point", point.index),
                             y: .value("Elevation", point.meters))
                        .foregroundStyle(ATHLTHStudioStyle.gold)
                }
                .frame(height: 155)
            } else {
                Text(tr(
                    "Elevation detail is unavailable for this saved route. The route is shown without an invented profile.",
                    "Høydedata mangler for denne ruten. Vi viser ikke en beregnet høydeprofil uten målinger."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private struct ElevationPoint: Identifiable {
        let index: Int
        let meters: Double
        var id: Int { index }
    }
}
