import CoreLocation
import MapKit
import SwiftUI

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
            manager.startUpdatingLocation()

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
                manager.startUpdatingLocation()
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
    @State private var mapPosition: MapCameraPosition = .automatic

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
                    AroundYouExploreView(
                        locationStore: locationStore
                    )
                } label: {
                    HStack(spacing: 5) {
                        Text("Explore")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }

            Map(position: $mapPosition) {
                if locationStore.canShowUserLocation {
                    UserAnnotation()
                }

                ForEach(nearbyRoutes.prefix(8)) { route in
                    MapPolyline(
                        coordinates: route.coordinates.map(\.coordinate)
                    )
                    .stroke(
                        route.isMine
                            ? ATHLTHTheme.premiumGold
                            : ATHLTHTheme.accent,
                        style: StrokeStyle(
                            lineWidth: route.isMine ? 5 : 4,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                    if let center = route.centerCoordinate {
                        Annotation(route.title, coordinate: center) {
                            Image(
                                systemName: route.isMine
                                    ? "figure.run.circle.fill"
                                    : "point.topleft.down.to.point.bottomright.curvepath"
                            )
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(
                                route.isMine
                                    ? ATHLTHTheme.premiumGold
                                    : ATHLTHTheme.accentDeep,
                                in: Circle()
                            )
                            .shadow(
                                color: .black.opacity(0.12),
                                radius: 7,
                                y: 4
                            )
                        }
                    }
                }

                ForEach(nearbyEvents.prefix(12)) { item in
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
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapUserLocationButton()
            }
            .frame(height: 235)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
            .overlay(alignment: .topLeading) {
                HStack(spacing: 7) {
                    Image(systemName: "location.fill")
                    Text(locationStore.location == nil ? "Finding you…" : "You are here")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
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
                    centerOnUser()
                } label: {
                    Image(systemName: "location.circle.fill")
                        .font(.title3)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh current location")
            }
            .padding(.top, 11)

            if let error = locationStore.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .task {
            async let routesRefresh: Void = routeDiscovery.refresh()
            async let eventsRefresh: Void = community.refresh()
            _ = await (routesRefresh, eventsRefresh)
        }
        .onAppear {
            locationStore.start()
            centerOnUser()
        }
        .onDisappear {
            locationStore.stop()
        }
        .onChange(of: locationStore.location?.timestamp) { _, _ in
            centerOnUser()
        }
    }

    private var locationSubtitle: String {
        if locationStore.location != nil {
            return "Live routes and events near your current location."
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
                isMine: route.ownerID == session.profile.userID
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
                isMine: true
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
                guard let center = route.centerCoordinate else {
                    return nil
                }

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

    private func centerOnUser() {
        guard let coordinate = locationStore.location?.coordinate else {
            return
        }

        withAnimation(.easeInOut(duration: 0.35)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: 0.10,
                        longitudeDelta: 0.10
                    )
                )
            )
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
                                Image(systemName: "figure.run.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(
                                        route.isMine
                                            ? ATHLTHTheme.premiumGold
                                            : ATHLTHTheme.accentDeep
                                    )
                                    .background(.white, in: Circle())
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
                    locationStore.refresh()
                    centerOnUser()
                } label: {
                    Image(systemName: "location.fill")
                }
                .accessibilityLabel("Center on my location")
            }
        }
        .task {
            async let routesRefresh: Void = routeDiscovery.refresh()
            async let eventsRefresh: Void = community.refresh()
            _ = await (routesRefresh, eventsRefresh)
        }
        .onAppear {
            locationStore.start()
            centerOnUser()
        }
        .onDisappear {
            locationStore.stop()
        }
        .onChange(of: locationStore.location?.timestamp) { _, _ in
            centerOnUser()
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
                isMine: route.ownerID == session.profile.userID
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
                isMine: true
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
