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
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var routeDiscovery: RouteDiscoveryStore

    @ObservedObject var locationStore: HomeLocationStore

    @State private var filter: AroundYouFilter = .all
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var hasCenteredOnUser = false
    @State private var selectedRoute: TrainingRoute?

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

            Map(position: $mapPosition) {
                if locationStore.canShowUserLocation {
                    UserAnnotation()
                }

                if filter != .events {
                    ForEach(nearbyRoutes.prefix(25)) { route in
                        MapPolyline(
                            coordinates: route.coordinates.map(\.coordinate)
                        )
                        .stroke(
                            route.isMine
                                ? ATHLTHTheme.premiumGold
                                : ATHLTHTheme.accent,
                            lineWidth: route.isMine ? 5 : 4
                        )

                        if let center = route.centerCoordinate {
                            Annotation(route.title, coordinate: center) {
                                Button {
                                    selectedRoute = route.trainingRoute
                                } label: {
                                    Image(systemName: "figure.run.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(
                                            route.isMine
                                                ? ATHLTHTheme.premiumGold
                                                : ATHLTHTheme.accentDeep
                                        )
                                        .background(.white, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    "Open \(route.title)"
                                )
                            }
                        }
                    }
                }

                if filter != .routes {
                    ForEach(nearbyEvents.prefix(30)) { item in
                        if let coordinate = eventCoordinate(item) {
                            Marker(
                                item.event.title,
                                systemImage: item.event.activityType.systemImage,
                                coordinate: coordinate
                            )
                            .tint(.purple)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
                MapUserLocationButton()
            }
        }
        .background(ATHLTHPremiumCanvas())
        .navigationTitle("Around You")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    hasCenteredOnUser = false
                    locationStore.refresh()
                    centerOnUser()
                } label: {
                    Image(systemName: "location.fill")
                }
                .accessibilityLabel("Center on my location")
            }
        }
        .task {
            async let routesRefresh: Void =
                routeDiscovery.refresh()
            async let eventsRefresh: Void = community.refresh()
            _ = await (routesRefresh, eventsRefresh)
        }
        .sheet(item: $selectedRoute) { route in
            NavigationStack {
                RouteDetailView(route: route)
            }
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
    }

    private var nearbyRoutes: [AroundYouRouteItem] {
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

        let values = Array(routesByID.values)

        guard let location = locationStore.location else {
            return values
        }

        return values
            .compactMap { route -> (AroundYouRouteItem, CLLocationDistance)? in
                guard let center = route.centerCoordinate else { return nil }
                let distance = CLLocation(
                    latitude: center.latitude,
                    longitude: center.longitude
                )
                .distance(from: location)
                guard distance <= 50_000 else { return nil }
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
            return candidates
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
                guard distance <= 50_000 else { return nil }
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

    private func centerOnUser() {
        guard let coordinate = locationStore.location?.coordinate else {
            return
        }

        hasCenteredOnUser = true

        withAnimation(.easeInOut(duration: 0.35)) {
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
