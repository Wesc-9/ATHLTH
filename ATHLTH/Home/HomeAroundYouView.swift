import CoreLocation
import MapKit
import SwiftUI
import UIKit

final class HomeLocationStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isUpdating = false
    @Published var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 75
        manager.pausesLocationUpdatesAutomatically = true
    }

    var canShowUserLocation: Bool {
        authorizationStatus == .authorizedWhenInUse ||
        authorizationStatus == .authorizedAlways
    }

    func start() {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()

        case .authorizedAlways, .authorizedWhenInUse:
            isUpdating = true
            manager.requestLocation()

        case .denied, .restricted:
            isUpdating = false
            errorMessage =
                "Location access is needed to center Around You on your current position."

        @unknown default:
            break
        }
    }

    func refresh() {
        guard canShowUserLocation else {
            start()
            return
        }

        isUpdating = true
        manager.requestLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        isUpdating = false
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.authorizationStatus = manager.authorizationStatus

            if self.canShowUserLocation {
                self.errorMessage = nil
                self.isUpdating = true
                manager.requestLocation()
            } else if manager.authorizationStatus == .denied ||
                        manager.authorizationStatus == .restricted {
                self.isUpdating = false
                self.errorMessage =
                    "Location access is off. Enable it in iOS Settings to show nearby routes and events."
            }
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let newest = locations.last else { return }

        DispatchQueue.main.async { [weak self] in
            self?.location = newest
            self?.isUpdating = false
            self?.errorMessage = nil
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        if let locationError = error as? CLError,
           locationError.code == .locationUnknown {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.isUpdating = false
            self?.errorMessage = error.localizedDescription
        }
    }
}

private struct AroundYouRouteItem: Identifiable {
    let id: UUID
    let title: String
    let distanceKilometers: Double
    let elevationGainMeters: Double?
    let coordinates: [RouteCoordinate]
    let ownerID: UUID
    let isMine: Bool
    let trainingRoute: TrainingRoute

    var centerCoordinate: CLLocationCoordinate2D? {
        guard !coordinates.isEmpty else { return nil }

        let latitude =
            coordinates.reduce(0) { $0 + $1.latitude } /
            Double(coordinates.count)
        let longitude =
            coordinates.reduce(0) { $0 + $1.longitude } /
            Double(coordinates.count)

        return CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }
}

private enum AroundYouFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case routes = "Routes"
    case events = "Events"

    var id: String { rawValue }
}

struct HomeAroundYouSection: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var routeDiscovery: RouteDiscoveryStore

    @StateObject private var locationStore = HomeLocationStore()
    @State private var mapSnapshot: UIImage?
    @State private var snapshotLoading = false

    var body: some View {
        ATHLTHCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Around You")
                        .font(.title3.weight(.bold))

                    Text(locationSubtitle)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()

                NavigationLink {
                    AroundYouExploreView(locationStore: locationStore)
                } label: {
                    HStack(spacing: 5) {
                        Text("Explore")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }

            NavigationLink {
                AroundYouExploreView(locationStore: locationStore)
            } label: {
                ZStack {
                    if let mapSnapshot {
                        Image(uiImage: mapSnapshot)
                            .resizable()
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [
                                ATHLTHTheme.surfaceSage,
                                ATHLTHTheme.cardWarm,
                                ATHLTHTheme.canvasBottom
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        VStack(spacing: 9) {
                            if snapshotLoading || locationStore.isUpdating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "map.fill")
                                    .font(.title2)
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                            }

                            Text(
                                locationStore.canShowUserLocation
                                    ? "Preparing nearby preview"
                                    : "Location is needed for nearby discovery"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                    }
                }
                .frame(height: 188)
                .frame(maxWidth: .infinity)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                    .stroke(Color.white.opacity(0.70), lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 7) {
                        Image(systemName: "location.fill")
                        Text(
                            locationStore.location == nil
                                ? "Finding you…"
                                : "You are here"
                        )
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
                }
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Around You map")
            .padding(.top, 12)

            HStack(spacing: 8) {
                discoveryCount(
                    title: "Routes",
                    count: nearbyRoutes.count,
                    icon: "point.topleft.down.to.point.bottomright.curvepath"
                )

                discoveryCount(
                    title: "Events",
                    count: nearbyEvents.count,
                    icon: "calendar"
                )

                Spacer()

                Button {
                    locationStore.refresh()
                } label: {
                    Image(systemName: "location.circle.fill")
                        .font(.title3)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh current location")
            }
            .padding(.top, 11)

            if let nearest = nearbyRoutes.first {
                Label(
                    "\(nearest.title) · \(nearest.distanceKilometers.formatted(.number.precision(.fractionLength(1)))) km",
                    systemImage: "figure.run"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.primaryText.opacity(0.78))
                .lineLimit(1)
                .padding(.top, 8)
            } else if let event = nearbyEvents.first {
                Label(
                    event.event.title,
                    systemImage: event.event.activityType.systemImage
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.primaryText.opacity(0.78))
                .lineLimit(1)
                .padding(.top, 8)
            }

            if let error = locationStore.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        // LazyVStack creates this section only when Home scrolls near it.
        // Discovery is read-only here; route publishing belongs to route edits.
        .task {
            locationStore.start()
            await routeDiscovery.refresh()
            await refreshSnapshot()
        }
        .onChange(of: locationStore.location?.timestamp) { _, _ in
            Task { await refreshSnapshot() }
        }
        .onChange(of: routeDiscovery.routes.count) { _, _ in
            Task { await refreshSnapshot() }
        }
        .onChange(of: community.events.count) { _, _ in
            Task { await refreshSnapshot() }
        }
    }

    private var locationSubtitle: String {
        if locationStore.location != nil {
            return "Routes and events near your current location."
        }

        if locationStore.canShowUserLocation {
            return "Updating nearby routes and events…"
        }

        return "Allow location to see what's happening around you."
    }

    private var allRoutes: [AroundYouRouteItem] {
        var routesByID: [UUID: AroundYouRouteItem] = [:]

        for route in routeDiscovery.routes {
            routesByID[route.id] = AroundYouRouteItem(
                id: route.id,
                title: route.title,
                distanceKilometers: route.distanceKilometers,
                elevationGainMeters: route.elevationGainMeters,
                coordinates: route.coordinates,
                ownerID: route.ownerID,
                isMine: route.ownerID == session.profile.userID,
                trainingRoute: route.trainingRoute
            )
        }

        for route in session.savedRoutes {
            routesByID[route.id] = AroundYouRouteItem(
                id: route.id,
                title: route.title,
                distanceKilometers: route.distanceKilometers,
                elevationGainMeters: route.elevationGainMeters,
                coordinates: route.coordinates,
                ownerID: route.ownerID,
                isMine: true,
                trainingRoute: route
            )
        }

        return Array(routesByID.values)
    }

    private var nearbyRoutes: [AroundYouRouteItem] {
        guard let location = locationStore.location else {
            return allRoutes
                .filter(\.isMine)
                .sorted { $0.title < $1.title }
        }

        return allRoutes
            .compactMap { route -> (AroundYouRouteItem, CLLocationDistance)? in
                guard let center = route.centerCoordinate else { return nil }

                let distance = CLLocation(
                    latitude: center.latitude,
                    longitude: center.longitude
                )
                .distance(from: location)

                guard distance <= 35_000 else { return nil }
                return (route, distance)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private var nearbyEvents: [CommunityEventItem] {
        let candidates = community.upcomingEvents.filter {
            $0.event.visibility == ProfileVisibility.publicProfile.rawValue
        }

        guard let location = locationStore.location else {
            return candidates.filter {
                $0.event.latitude != nil &&
                $0.event.longitude != nil
            }
        }

        return candidates
            .compactMap { item -> (CommunityEventItem, CLLocationDistance)? in
                guard let coordinate = eventCoordinate(item) else {
                    return nil
                }

                let distance = CLLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
                .distance(from: location)

                guard distance <= 35_000 else { return nil }
                return (item, distance)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private func eventCoordinate(
        _ item: CommunityEventItem
    ) -> CLLocationCoordinate2D? {
        guard let latitude = item.event.latitude,
              let longitude = item.event.longitude
        else {
            return nil
        }

        return CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }

    @MainActor
    private func refreshSnapshot() async {
        guard let location = locationStore.location else { return }
        guard !snapshotLoading else { return }

        snapshotLoading = true
        defer { snapshotLoading = false }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: 0.10,
                longitudeDelta: 0.10
            )
        )
        options.size = CGSize(width: 900, height: 420)
        options.scale = 1
        options.mapType = .standard
        options.showsBuildings = true

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            let bounds = CGRect(origin: .zero, size: options.size)
            let renderer = UIGraphicsImageRenderer(size: options.size)

            mapSnapshot = renderer.image { context in
                snapshot.image.draw(at: .zero)

                let cg = context.cgContext
                cg.setLineCap(.round)
                cg.setLineJoin(.round)

                for route in nearbyRoutes.prefix(4) {
                    let points = route.coordinates
                        .enumerated()
                        .compactMap { index, coordinate -> CGPoint? in
                            let stride = max(route.coordinates.count / 90, 1)
                            guard index % stride == 0 ||
                                  index == route.coordinates.count - 1
                            else { return nil }

                            let point = snapshot.point(
                                for: coordinate.coordinate
                            )
                            return bounds.insetBy(dx: -20, dy: -20)
                                .contains(point) ? point : nil
                        }

                    guard points.count > 1 else { continue }

                    cg.beginPath()
                    cg.move(to: points[0])
                    for point in points.dropFirst() {
                        cg.addLine(to: point)
                    }
                    cg.setStrokeColor(
                        route.isMine
                            ? UIColor.systemOrange.cgColor
                            : UIColor.systemGreen.cgColor
                    )
                    cg.setLineWidth(route.isMine ? 7 : 6)
                    cg.strokePath()
                }

                for item in nearbyEvents.prefix(8) {
                    guard let coordinate = eventCoordinate(item) else {
                        continue
                    }

                    let point = snapshot.point(for: coordinate)
                    guard bounds.contains(point) else { continue }

                    cg.setFillColor(UIColor.systemPurple.cgColor)
                    cg.fillEllipse(
                        in: CGRect(
                            x: point.x - 7,
                            y: point.y - 7,
                            width: 14,
                            height: 14
                        )
                    )
                }

                let userPoint = snapshot.point(for: location.coordinate)
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillEllipse(
                    in: CGRect(
                        x: userPoint.x - 11,
                        y: userPoint.y - 11,
                        width: 22,
                        height: 22
                    )
                )
                cg.setFillColor(UIColor.systemBlue.cgColor)
                cg.fillEllipse(
                    in: CGRect(
                        x: userPoint.x - 7,
                        y: userPoint.y - 7,
                        width: 14,
                        height: 14
                    )
                )
            }
        } catch {
            // Keep the lightweight fallback instead of turning map rendering
            // into a Home-level error.
        }
    }

    private func discoveryCount(
        title: String,
        count: Int,
        icon: String
    ) -> some View {
        Label(
            "\(count) \(title.lowercased())",
            systemImage: icon
        )
        .font(.caption2.weight(.semibold))
        .foregroundStyle(ATHLTHTheme.mutedText)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Color.primary.opacity(0.035),
            in: Capsule()
        )
    }
}

struct AroundYouExploreView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var routeDiscovery: RouteDiscoveryStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    @ObservedObject var locationStore: HomeLocationStore

    @StateObject private var routeAttempts = RouteAttemptStore()

    @State private var filter: AroundYouFilter = .all
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var hasCenteredOnUser = false
    @State private var selectedRoute: TrainingRoute?
    @State private var routeActionMessage: String?
    @State private var routeActionError: String?
    @State private var startingRoute = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Map filter", selection: $filter) {
                ForEach(AroundYouFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            MapReader { proxy in
                Map(position: $mapPosition) {
                    if locationStore.canShowUserLocation {
                        UserAnnotation()
                    }

                    if filter != .events {
                        ForEach(nearbyRoutes.prefix(25)) { route in
                            let isSelected =
                                selectedRoute?.id == route.id

                            MapPolyline(
                                coordinates:
                                    route.coordinates.map(\.coordinate)
                            )
                            .stroke(
                                route.isMine
                                    ? ATHLTHTheme.premiumGold
                                    : ATHLTHTheme.accent,
                                lineWidth: isSelected
                                    ? 7
                                    : (route.isMine ? 5 : 4)
                            )

                            if let center = route.centerCoordinate {
                                Annotation(
                                    route.title,
                                    coordinate: center
                                ) {
                                    Button {
                                        selectRoute(
                                            route.trainingRoute
                                        )
                                    } label: {
                                        Image(
                                            systemName:
                                                isSelected
                                                    ? "figure.run.circle.fill"
                                                    : "figure.run.circle"
                                        )
                                        .font(
                                            isSelected
                                                ? .title2
                                                : .title3
                                        )
                                        .foregroundStyle(
                                            route.isMine
                                                ? ATHLTHTheme.premiumGold
                                                : ATHLTHTheme.accentDeep
                                        )
                                        .background(
                                            .white,
                                            in: Circle()
                                        )
                                        .shadow(
                                            color: .black.opacity(
                                                isSelected
                                                    ? 0.16
                                                    : 0.08
                                            ),
                                            radius:
                                                isSelected ? 7 : 3,
                                            y: 2
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(
                                        "Preview \(route.title)"
                                    )
                                }
                            }
                        }
                    }

                    if filter != .routes {
                        ForEach(nearbyEvents.prefix(30)) { item in
                            if let coordinate =
                                eventCoordinate(item) {
                                Marker(
                                    item.event.title,
                                    systemImage:
                                        item.event
                                            .activityType
                                            .systemImage,
                                    coordinate: coordinate
                                )
                                .tint(.purple)
                            }
                        }
                    }
                }
                .mapStyle(
                    .standard(elevation: .realistic)
                )
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }
                .onTapGesture { point in
                    guard let coordinate = proxy.convert(
                        point,
                        from: .local
                    ) else {
                        return
                    }

                    selectRoute(
                        nearestTo: coordinate
                    )
                }
                .overlay(alignment: .bottom) {
                    if let route = selectedRoute {
                        routePreviewCard(route)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                            .transition(
                                .move(edge: .bottom)
                                    .combined(with: .opacity)
                            )
                            .zIndex(10)
                    }
                }
                .animation(
                    .spring(
                        response: 0.34,
                        dampingFraction: 0.86
                    ),
                    value: selectedRoute?.id
                )
            }
        }
        .background(ATHLTHPremiumCanvas())
        .navigationTitle("Around You")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    hasCenteredOnUser = false
                    locationStore.refresh()
                    centerOnUser()
                } label: {
                    Image(systemName: "location.fill")
                }
                .accessibilityLabel(
                    "Center on my location"
                )
            }
        }
        .task {
            async let routesRefresh: Void =
                routeDiscovery.refresh()
            async let eventsRefresh: Void =
                community.refresh()
            _ = await (
                routesRefresh,
                eventsRefresh
            )
        }
        .task(id: selectedRoute?.id) {
            guard let selectedRoute else {
                return
            }

            await routeAttempts.refresh(
                routeID: selectedRoute.id
            )
        }
        .onAppear {
            locationStore.start()
            centerOnUser()
        }
        .onDisappear {
            locationStore.stop()
        }
        .onChange(of: locationStore.location?.timestamp) { _, _ in
            if !hasCenteredOnUser {
                centerOnUser()
            }
        }
        .onChange(of: filter) { _, _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedRoute = nil
            }
        }
        .alert(
            "ATHLTH",
            isPresented: Binding(
                get: {
                    routeActionMessage != nil ||
                    routeActionError != nil
                },
                set: { visible in
                    if !visible {
                        routeActionMessage = nil
                        routeActionError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                routeActionError ??
                routeActionMessage ??
                ""
            )
        }
    }

    private func selectRoute(
        _ route: TrainingRoute
    ) {
        withAnimation(
            .spring(
                response: 0.34,
                dampingFraction: 0.86
            )
        ) {
            selectedRoute = route
        }
    }

    private func selectRoute(
        nearestTo coordinate: CLLocationCoordinate2D
    ) {
        guard filter != .events else {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedRoute = nil
            }
            return
        }

        let tapLocation = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        let candidate = nearbyRoutes
            .prefix(25)
            .compactMap {
                route ->
                    (TrainingRoute, CLLocationDistance)?
                in
                guard !route.coordinates.isEmpty
                else {
                    return nil
                }

                let strideValue = max(
                    route.coordinates.count / 140,
                    1
                )

                let sampled = route.coordinates
                    .enumerated()
                    .compactMap {
                        index,
                        point -> CLLocation? in
                        guard
                            index % strideValue == 0 ||
                            index ==
                                route.coordinates.count - 1
                        else {
                            return nil
                        }

                        return CLLocation(
                            latitude: point.latitude,
                            longitude: point.longitude
                        )
                    }

                guard let nearest = sampled
                    .lazy
                    .map({
                        tapLocation.distance(from: $0)
                    })
                    .min(),
                    nearest <= 240
                else {
                    return nil
                }

                return (
                    route.trainingRoute,
                    nearest
                )
            }
            .min { $0.1 < $1.1 }

        if let route = candidate?.0 {
            selectRoute(route)
        } else {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedRoute = nil
            }
        }
    }

    private func routePreviewCard(
        _ route: TrainingRoute
    ) -> some View {
        let leaderboard = previewLeaderboard(
            for: route
        )
        let topThree = Array(
            leaderboard.prefix(3)
        )
        let fastest = leaderboard.first
        let saved = isRouteSaved(route)
        let creator = creatorProfile(for: route)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                creatorAvatar(
                    route: route,
                    profile: creator
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(route.title)
                        .font(.headline)
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(1)

                    Text(
                        creatorLabel(
                            route: route,
                            profile: creator
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)
                }

                Spacer()

                Button {
                    withAnimation(
                        .easeInOut(duration: 0.18)
                    ) {
                        selectedRoute = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(
                            .system(
                                size: 10,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .frame(width: 28, height: 28)
                        .background(
                            Color.primary.opacity(0.055),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Close route preview"
                )
            }

            HStack(spacing: 8) {
                previewMetric(
                    value: String(
                        format: "%.1f km",
                        route.distanceKilometers
                    ),
                    icon: "figure.run"
                )

                if let elevation =
                    route.elevationGainMeters {
                    previewMetric(
                        value:
                            "\(Int(elevation.rounded())) m ↑",
                        icon: "mountain.2.fill"
                    )
                }

                if let distance =
                    distanceToRouteStart(route) {
                    previewMetric(
                        value: distance,
                        icon: "location.fill"
                    )
                }

                previewMetric(
                    value:
                        "\(previewAttemptCount(for: route))",
                    icon:
                        "arrow.trianglehead.2.clockwise.rotate.90"
                )
            }

            if routeAttempts.isLoading &&
               routeAttempts.loadedRouteID != route.id {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Loading route times…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 46)
            } else if let fastest {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(
                            "Fastest",
                            systemImage: "trophy.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.premiumGold
                        )

                        Spacer()

                        Text(
                            routeClock(
                                fastest.durationSeconds
                            )
                        )
                        .font(
                            .subheadline
                                .monospacedDigit()
                                .weight(.bold)
                        )
                    }

                    HStack(spacing: 6) {
                        ForEach(
                            Array(topThree.enumerated()),
                            id: \.element.id
                        ) { index, attempt in
                            leaderboardChip(
                                attempt,
                                rank: index + 1
                            )
                        }
                    }
                }
            } else {
                Label(
                    "No qualifying times yet",
                    systemImage: "trophy"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 46)
            }

            HStack(spacing: 8) {
                if route.ownerID !=
                    session.profile.userID {
                    Button {
                        if !saved {
                            session.saveSharedRoute(
                                route,
                                sourceOwnerID: route.ownerID,
                                sourceRouteID: route.id
                            )
                            routeActionMessage =
                                "Route saved to My Routes."
                        }
                    } label: {
                        Label(
                            saved ? "Saved" : "Save",
                            systemImage:
                                saved
                                    ? "bookmark.fill"
                                    : "bookmark"
                        )
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                    }
                    .buttonStyle(.bordered)
                    .disabled(saved)
                }

                if settings.trainingDeviceProvider ==
                    .appleWatch {
                    Button {
                        Task {
                            await startRouteOnWatch(
                                route
                            )
                        }
                    } label: {
                        if startingRoute {
                            ProgressView()
                                .controlSize(.small)
                                .frame(
                                    maxWidth: .infinity
                                )
                        } else {
                            Label(
                                "Start",
                                systemImage: "play.fill"
                            )
                            .font(
                                .caption.weight(.semibold)
                            )
                            .frame(
                                maxWidth: .infinity
                            )
                        }
                    }
                    .frame(height: 38)
                    .buttonStyle(.bordered)
                    .disabled(
                        startingRoute ||
                        !watchConnection.isReady
                    )
                }

                NavigationLink {
                    RouteDetailView(route: route)
                } label: {
                    HStack(spacing: 5) {
                        Text("Details")
                        Image(
                            systemName: "chevron.right"
                        )
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accent)
            }
        }
        .padding(14)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.72),
                lineWidth: 1
            )
        }
        .shadow(
            color: .black.opacity(0.12),
            radius: 18,
            y: 7
        )
    }

    private func previewMetric(
        value: String,
        icon: String
    ) -> some View {
        Label(value, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(
                ATHLTHTheme.primaryText.opacity(0.78)
            )
            .padding(.horizontal, 8)
            .frame(height: 27)
            .background(
                Color.primary.opacity(0.04),
                in: Capsule()
            )
            .lineLimit(1)
    }

    private func leaderboardChip(
        _ attempt: RouteAttemptRecord,
        rank: Int
    ) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Text("#\(rank)")
                    .foregroundStyle(
                        rank == 1
                            ? ATHLTHTheme.premiumGold
                            : ATHLTHTheme.mutedText
                    )

                Text(
                    attempt.userID ==
                        session.profile.userID
                        ? "You"
                        : compactAthleteName(attempt)
                )
                .lineLimit(1)
            }
            .font(
                .system(
                    size: 9,
                    weight: .semibold
                )
            )

            Text(
                routeClock(
                    attempt.durationSeconds
                )
            )
            .font(
                .caption
                    .monospacedDigit()
                    .weight(.bold)
            )
        }
        .foregroundStyle(ATHLTHTheme.primaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(
                cornerRadius: 11,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private func creatorAvatar(
        route: TrainingRoute,
        profile: SocialProfileCard?
    ) -> some View {
        if let url = creatorAvatarURL(
            route: route,
            profile: profile
        ) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    creatorAvatarFallback
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
        } else {
            creatorAvatarFallback
                .frame(width: 38, height: 38)
        }
    }

    private var creatorAvatarFallback: some View {
        Circle()
            .fill(ATHLTHTheme.accentSoft)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.accent
                    )
            }
    }

    private func creatorProfile(
        for route: TrainingRoute
    ) -> SocialProfileCard? {
        social.visibleProfiles.first {
            $0.userID == route.ownerID
        }
    }

    private func creatorLabel(
        route: TrainingRoute,
        profile: SocialProfileCard?
    ) -> String {
        if route.ownerID == session.profile.userID {
            let username = session.profile.username
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            return username.isEmpty
                ? "Created by you"
                : "Created by @\(username)"
        }

        if let username = profile?.username,
           !username.isEmpty {
            return "Created by @\(username)"
        }

        if let profile {
            return "Created by \(profile.resolvedName)"
        }

        return "Created by ATHLTH athlete"
    }

    private func creatorAvatarURL(
        route: TrainingRoute,
        profile: SocialProfileCard?
    ) -> URL? {
        if route.ownerID == session.profile.userID {
            return session.profile.avatarURL
        }

        guard let value = profile?.avatarURL else {
            return nil
        }

        return URL(string: value)
    }

    private func previewLeaderboard(
        for route: TrainingRoute
    ) -> [RouteAttemptRecord] {
        guard routeAttempts.loadedRouteID == route.id
        else {
            return []
        }

        return routeAttempts.leaderboard()
    }

    private func previewAttemptCount(
        for route: TrainingRoute
    ) -> Int {
        guard routeAttempts.loadedRouteID == route.id
        else {
            return 0
        }

        return routeAttempts.attempts.count
    }

    private func isRouteSaved(
        _ route: TrainingRoute
    ) -> Bool {
        if route.ownerID == session.profile.userID {
            return true
        }

        return session.savedRoutes.contains {
            $0.id == route.id ||
            $0.sharedSourceRouteID == route.id
        }
    }

    private func distanceToRouteStart(
        _ route: TrainingRoute
    ) -> String? {
        guard let userLocation =
                locationStore.location,
              let first =
                route.coordinates.first
        else {
            return nil
        }

        let start = CLLocation(
            latitude: first.latitude,
            longitude: first.longitude
        )
        let meters =
            userLocation.distance(from: start)

        if meters < 1_000 {
            return "\(Int(meters.rounded())) m"
        }

        return String(
            format: "%.1f km",
            meters / 1_000
        )
    }

    private func compactAthleteName(
        _ attempt: RouteAttemptRecord
    ) -> String {
        if let username = attempt.username,
           !username.isEmpty {
            return "@\(username)"
        }

        let name = attempt.athleteName
        if name.count > 12 {
            return String(name.prefix(11)) + "…"
        }

        return name
    }

    private func routeClock(
        _ duration: TimeInterval
    ) -> String {
        let seconds =
            max(Int(duration.rounded()), 0)
        let hours = seconds / 3_600
        let minutes =
            (seconds % 3_600) / 60
        let remainder = seconds % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                remainder
            )
        }

        return String(
            format: "%d:%02d",
            minutes,
            remainder
        )
    }

    private func startRouteOnWatch(
        _ route: TrainingRoute
    ) async {
        guard watchConnection.isReady else {
            routeActionError =
                "Apple Watch is not ready."
            return
        }

        startingRoute = true
        defer { startingRoute = false }

        do {
            try watchConnection.sendRoute(route)
            watchConnection.sendWorkoutRouteSelection(
                route.id
            )
            try await watchConnection
                .startWorkoutOnWatch(.running)

            routeActionMessage =
                "\(route.title) started on Apple Watch."
        } catch {
            routeActionError =
                error.localizedDescription
        }
    }

    private var nearbyRoutes: [AroundYouRouteItem] {
        var routesByID:
            [UUID: AroundYouRouteItem] = [:]

        for route in routeDiscovery.routes {
            routesByID[route.id] =
                AroundYouRouteItem(
                    id: route.id,
                    title: route.title,
                    distanceKilometers:
                        route.distanceKilometers,
                    elevationGainMeters:
                        route.elevationGainMeters,
                    coordinates: route.coordinates,
                    ownerID: route.ownerID,
                    isMine:
                        route.ownerID ==
                        session.profile.userID,
                    trainingRoute:
                        route.trainingRoute
                )
        }

        for route in session.savedRoutes {
            routesByID[route.id] =
                AroundYouRouteItem(
                    id: route.id,
                    title: route.title,
                    distanceKilometers:
                        route.distanceKilometers,
                    elevationGainMeters:
                        route.elevationGainMeters,
                    coordinates:
                        route.coordinates,
                    ownerID: route.ownerID,
                    isMine: true,
                    trainingRoute: route
                )
        }

        let values =
            Array(routesByID.values)

        guard let location =
                locationStore.location
        else {
            return values
        }

        return values
            .compactMap {
                route ->
                    (
                        AroundYouRouteItem,
                        CLLocationDistance
                    )?
                in
                guard let center =
                        route.centerCoordinate
                else {
                    return nil
                }

                let distance = CLLocation(
                    latitude: center.latitude,
                    longitude: center.longitude
                )
                .distance(from: location)

                guard distance <= 50_000 else {
                    return nil
                }

                return (route, distance)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private var nearbyEvents:
        [CommunityEventItem] {
        let candidates =
            community.upcomingEvents.filter {
                $0.event.visibility ==
                    ProfileVisibility
                        .publicProfile
                        .rawValue
            }

        guard let location =
                locationStore.location
        else {
            return candidates
        }

        return candidates
            .compactMap {
                item ->
                    (
                        CommunityEventItem,
                        CLLocationDistance
                    )?
                in
                guard let coordinate =
                        eventCoordinate(item)
                else {
                    return nil
                }

                let distance = CLLocation(
                    latitude:
                        coordinate.latitude,
                    longitude:
                        coordinate.longitude
                )
                .distance(from: location)

                guard distance <= 50_000
                else {
                    return nil
                }

                return (item, distance)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private func eventCoordinate(
        _ item: CommunityEventItem
    ) -> CLLocationCoordinate2D? {
        guard let latitude =
                item.event.latitude,
              let longitude =
                item.event.longitude
        else {
            return nil
        }

        return CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }

    private func centerOnUser() {
        guard let coordinate =
                locationStore.location?.coordinate
        else {
            return
        }

        hasCenteredOnUser = true

        withAnimation(
            .easeInOut(duration: 0.35)
        ) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: 0.12,
                        longitudeDelta: 0.12
                    )
                )
            )
        }
    }
}
