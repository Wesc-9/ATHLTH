@preconcurrency import CoreLocation
import MapKit
import SwiftUI
import UIKit

@MainActor
final class HomeLocationStore: NSObject, ObservableObject, CLLocationManagerDelegate, @unchecked Sendable {
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

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        let status = manager.authorizationStatus

        Task { @MainActor [weak self] in
            guard let self else { return }

            self.authorizationStatus = status

            if self.canShowUserLocation {
                self.errorMessage = nil
                self.isUpdating = true
                self.manager.requestLocation()
            } else if status == .denied || status == .restricted {
                self.isUpdating = false
                self.errorMessage =
                    "Location access is off. Enable it in iOS Settings to show nearby routes and events."
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let newest = locations.last else { return }

        let latitude = newest.coordinate.latitude
        let longitude = newest.coordinate.longitude
        let altitude = newest.altitude
        let horizontalAccuracy = newest.horizontalAccuracy
        let verticalAccuracy = newest.verticalAccuracy
        let course = newest.course
        let speed = newest.speed
        let timestamp = newest.timestamp

        Task { @MainActor [weak self] in
            self?.location = CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: latitude,
                    longitude: longitude
                ),
                altitude: altitude,
                horizontalAccuracy: horizontalAccuracy,
                verticalAccuracy: verticalAccuracy,
                course: course,
                speed: speed,
                timestamp: timestamp
            )
            self?.isUpdating = false
            self?.errorMessage = nil
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        if let locationError = error as? CLError,
           locationError.code == .locationUnknown {
            return
        }

        let message = error.localizedDescription

        Task { @MainActor [weak self] in
            self?.isUpdating = false
            self?.errorMessage = message
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
    let isPublicTrail: Bool
    let trainingRoute: TrainingRoute
    let centerCoordinate: CLLocationCoordinate2D?
    let renderCoordinates: [CLLocationCoordinate2D]
    let hitTestLocations: [CLLocation]

    init(
        id: UUID,
        title: String,
        distanceKilometers: Double,
        elevationGainMeters: Double?,
        coordinates: [RouteCoordinate],
        ownerID: UUID,
        isMine: Bool,
        isPublicTrail: Bool = false,
        trainingRoute: TrainingRoute
    ) {
        self.id = id
        self.title = title
        self.distanceKilometers = distanceKilometers
        self.elevationGainMeters = elevationGainMeters
        self.coordinates = coordinates
        self.ownerID = ownerID
        self.isMine = isMine
        self.isPublicTrail = isPublicTrail
        self.trainingRoute = trainingRoute

        if coordinates.isEmpty {
            centerCoordinate = nil
            renderCoordinates = []
            hitTestLocations = []
            return
        }

        let latitude =
            coordinates.reduce(0) { $0 + $1.latitude } /
            Double(coordinates.count)
        let longitude =
            coordinates.reduce(0) { $0 + $1.longitude } /
            Double(coordinates.count)

        centerCoordinate = CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )

        func sampled(
            maximumCount: Int
        ) -> [RouteCoordinate] {
            guard coordinates.count > maximumCount else {
                return coordinates
            }

            let strideValue = max(
                coordinates.count / maximumCount,
                1
            )

            var result = coordinates.enumerated().compactMap {
                index,
                point -> RouteCoordinate? in
                guard index % strideValue == 0 else {
                    return nil
                }
                return point
            }

            if let last = coordinates.last,
               result.last?.latitude != last.latitude ||
                result.last?.longitude != last.longitude {
                result.append(last)
            }

            return result
        }

        renderCoordinates = sampled(maximumCount: 180)
            .map(\.coordinate)

        hitTestLocations = sampled(maximumCount: 140)
            .map {
                CLLocation(
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            }
    }
}

private enum AroundYouFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case routes = "Routes"
    case events = "Events"

    var id: String { rawValue }
}

private enum ExploreRouteLengthFilter:
    String,
    CaseIterable,
    Identifiable {
    case any = "Any distance"
    case under3 = "Under 3 km"
    case threeToFive = "3–5 km"
    case fiveToTen = "5–10 km"
    case tenToTwenty = "10–20 km"
    case twentyPlus = "20+ km"

    var id: String { rawValue }

    func matches(_ kilometers: Double) -> Bool {
        switch self {
        case .any:
            return true
        case .under3:
            return kilometers < 3
        case .threeToFive:
            return kilometers >= 3 &&
                kilometers < 5
        case .fiveToTen:
            return kilometers >= 5 &&
                kilometers < 10
        case .tenToTwenty:
            return kilometers >= 10 &&
                kilometers < 20
        case .twentyPlus:
            return kilometers >= 20
        }
    }
}

private enum ExploreRouteSort:
    String,
    CaseIterable,
    Identifiable {
    case nearest = "Nearest"
    case shortest = "Shortest"
    case longest = "Longest"

    var id: String { rawValue }
}

struct HomeAroundYouSection: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var routeDiscovery: RouteDiscoveryStore
    @EnvironmentObject private var publicTrailDiscovery: PublicTrailDiscoveryStore

    @StateObject private var locationStore = HomeLocationStore()
    @State private var mapSnapshot: UIImage?
    @State private var snapshotLoading = false
    @State private var lastSnapshotLocation: CLLocation?
    private let snapshotMovementThreshold: CLLocationDistance = 150

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
                    title:
                        ATHLTHLocalization
                            .string("Routes"),
                    count: nearbyRoutes.count,
                    icon: "point.topleft.down.to.point.bottomright.curvepath"
                )

                discoveryCount(
                    title:
                        ATHLTHLocalization
                            .string("Events"),
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

            if let location = locationStore.location {
                await publicTrailDiscovery.refresh(
                    near: location
                )
            }

            await refreshSnapshot()
        }
        .task(id: locationStore.location?.timestamp) {
            guard let location = locationStore.location
            else {
                return
            }

            await publicTrailDiscovery.refresh(
                near: location
            )
            await refreshSnapshot(force: true)
        }
        .onChange(of: routeDiscovery.routes.count) { _, _ in
            Task { await refreshSnapshot(force: true) }
        }
        .onChange(of: community.events.count) { _, _ in
            Task { await refreshSnapshot(force: true) }
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

        for trail in publicTrailDiscovery.trails {
            let route = trail.trainingRoute

            routesByID[route.id] = AroundYouRouteItem(
                id: route.id,
                title: route.title,
                distanceKilometers:
                    route.distanceKilometers,
                elevationGainMeters:
                    route.elevationGainMeters,
                coordinates:
                    route.coordinates,
                ownerID:
                    route.ownerID,
                isMine: false,
                isPublicTrail: true,
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
    private func refreshSnapshot(
        force: Bool = false
    ) async {
        guard let location = locationStore.location else { return }
        guard !snapshotLoading else { return }

        if !force,
           mapSnapshot != nil,
           let lastSnapshotLocation,
           location.distance(from: lastSnapshotLocation) <
                snapshotMovementThreshold {
            return
        }

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
                    let points = route.renderCoordinates
                        .compactMap { coordinate -> CGPoint? in
                            let point = snapshot.point(
                                for: coordinate
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
            lastSnapshotLocation = location
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
    @EnvironmentObject private var publicTrailDiscovery: PublicTrailDiscoveryStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var spotify: SpotifyPlaybackStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @EnvironmentObject private var challenges: ChallengeStore

    @ObservedObject var locationStore: HomeLocationStore
    var embeddedInTab: Bool = false

    @StateObject private var routeAttempts = RouteAttemptStore()
    @StateObject private var publicTrailAttempts =
        PublicTrailAttemptStore()

    @State private var filter: AroundYouFilter = .all
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var hasCenteredOnUser = false
    @State private var selectedRoute: TrainingRoute?
    @State private var routeActionMessage: String?
    @State private var routeActionError: String?
    @State private var startingRoute = false
    @State private var routeToStart: TrainingRoute?
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var hasSeenInitialCamera = false
    @State private var shouldSearchVisibleArea = false
    @State private var isSearchingVisibleArea = false
    @State private var activeSearchCenter: CLLocation?
    @State private var suppressNextSearchPrompt = false
    @State private var routeLengthFilter:
        ExploreRouteLengthFilter = .any
    @State private var routeSort:
        ExploreRouteSort = .nearest

    var body: some View {
        ZStack {
            MapReader { proxy in
                Map(position: $mapPosition) {
                    if locationStore.canShowUserLocation {
                        UserAnnotation()
                    }

                    if filter == .all || filter == .routes {
                        ForEach(nearbyRoutes.prefix(35)) { route in
                            let isSelected =
                                selectedRoute?.id == route.id
                            let isDimmed =
                                selectedRoute != nil &&
                                !isSelected

                            MapPolyline(
                                coordinates:
                                    route.renderCoordinates
                            )
                            .stroke(
                                isDimmed
                                    ? Color.secondary.opacity(0.28)
                                    : route.isMine
                                        ? ATHLTHTheme.premiumGold
                                        : route.isPublicTrail
                                            ? ATHLTHTheme.vitality
                                            : ATHLTHTheme.accent,
                                lineWidth: isSelected
                                    ? 8
                                    : isDimmed
                                        ? 2.5
                                        : (
                                            route.isMine
                                                ? 5
                                                : route.isPublicTrail
                                                    ? 4.5
                                                    : 4
                                        )
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
                                                : route.isPublicTrail
                                                    ? ATHLTHTheme.vitality
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
                                    .opacity(isDimmed ? 0.34 : 1)
                                    .accessibilityLabel(
                                        ATHLTHLocalization.format(
                                            english: "Preview %@",
                                            norwegian: "Forhåndsvis %@",
                                            route.title
                                        )
                                    )
                                }
                            }
                        }
                    }

                    if filter == .all || filter == .events {
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
                }
                .onMapCameraChange(
                    frequency: .onEnd
                ) { context in
                    visibleRegion = context.region

                    if suppressNextSearchPrompt {
                        suppressNextSearchPrompt = false
                        shouldSearchVisibleArea = false
                    } else if hasSeenInitialCamera {
                        shouldSearchVisibleArea = true
                    } else {
                        hasSeenInitialCamera = true
                    }
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
                .overlay(alignment: .bottomLeading) {
                    if !publicTrailDiscovery
                        .trails
                        .isEmpty {
                        HStack(spacing: 5) {
                            Image(
                                systemName: "map.fill"
                            )
                            Text(
                                publicTrailDiscovery
                                    .attribution
                            )
                        }
                        .font(
                            .system(
                                size: 9,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                                .opacity(0.72)
                        )
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(
                            .ultraThinMaterial,
                            in: Capsule()
                        )
                        // Keep open-data attribution immediately above MapKit's
                        // own map-rights/legal attribution in the lower-left.
                        .padding(.leading, 10)
                        .padding(.bottom, 34)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let route = selectedRoute {
                        routePreviewCard(route)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
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

            exploreFloatingControls
                .frame(
                    maxHeight: .infinity,
                    alignment: .top
                )
                .allowsHitTesting(true)
        }
        .background(ATHLTHPremiumCanvas())
        .ignoresSafeArea(
            .container,
            edges: embeddedInTab ? .top : []
        )
        .navigationTitle(
            embeddedInTab ? "" : "Around You"
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(
            embeddedInTab ? .hidden : .visible,
            for: .navigationBar
        )
        .toolbar(
            embeddedInTab ? .visible : .hidden,
            for: .tabBar
        )
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
        .task(id: locationStore.location?.timestamp) {
            guard let location = locationStore.location
            else {
                return
            }

            if activeSearchCenter == nil {
                activeSearchCenter = location
            }

            await publicTrailDiscovery.refresh(
                near: location
            )
        }
        .task(id: selectedRoute?.id) {
            guard let selectedRoute else {
                return
            }

            if isPublicTrailRoute(
                selectedRoute
            ) {
                await publicTrailAttempts.refresh(
                    trailID:
                        publicTrailID(
                            for: selectedRoute
                        )
                )
            } else {
                await routeAttempts.refresh(
                    routeID: selectedRoute.id
                )
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
        .onChange(of: filter) { _, _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedRoute = nil
            }
        }
        .sheet(item: $routeToStart) { route in
            RunQuickStartSheet(
                trainingDeviceProvider:
                    watchConnection.isReady
                        ? .appleWatch
                        : .none,
                watchConnected: watchConnection.isReady,
                initialRoute: route
            ) { configuration in
                launchRunFromExplore(configuration)
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

    private var exploreFloatingControls:
        some View {
        VStack(spacing: 10) {
            if embeddedInTab {
                Text("Explore")
                    .font(
                        .system(
                            size: 22,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .shadow(
                        color:
                            Color.black.opacity(0.24),
                        radius: 5,
                        y: 2
                    )
                    .padding(.bottom, 2)
            }

            HStack(spacing: 8) {
                Button {
                    locationStore.start()
                    centerOnUser()
                } label: {
                    Image(
                        systemName:
                            "location.north.fill"
                    )
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .frame(
                        width: 48,
                        height: 48
                    )
                    .background(
                        .ultraThinMaterial,
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                Color.white.opacity(
                                    0.78
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color:
                            .black.opacity(0.12),
                        radius: 10,
                        y: 4
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    ATHLTHLocalization.choose(
                        english:
                            "Center on my location",
                        norwegian:
                            "Sentrer på min posisjon"
                    )
                )

                Picker(
                    "Map filter",
                    selection: $filter
                ) {
                    ForEach(
                        AroundYouFilter.allCases
                    ) { option in
                        Text(option.rawValue)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(3)
                .background(
                    .ultraThinMaterial,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            Color.white.opacity(
                                0.72
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color:
                        .black.opacity(0.10),
                    radius: 9,
                    y: 4
                )

                Menu {
                    Picker(
                        "Distance",
                        selection:
                            $routeLengthFilter
                    ) {
                        ForEach(
                            ExploreRouteLengthFilter
                                .allCases
                        ) { option in
                            Text(option.rawValue)
                                .tag(option)
                        }
                    }

                    Divider()

                    Picker(
                        "Sort",
                        selection: $routeSort
                    ) {
                        ForEach(
                            ExploreRouteSort
                                .allCases
                        ) { option in
                            Text(option.rawValue)
                                .tag(option)
                        }
                    }
                } label: {
                    Image(
                        systemName:
                            routeLengthFilter ==
                                .any &&
                            routeSort ==
                                .nearest
                                ? "slider.horizontal.3"
                                : "slider.horizontal.3.circle.fill"
                    )
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        routeLengthFilter ==
                            .any &&
                        routeSort ==
                            .nearest
                            ? ATHLTHTheme
                                .accentDeep
                            : ATHLTHTheme
                                .vitality
                    )
                    .frame(
                        width: 48,
                        height: 48
                    )
                    .background(
                        .ultraThinMaterial,
                        in:
                            RoundedRectangle(
                                cornerRadius: 15,
                                style:
                                    .continuous
                            )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                        .stroke(
                            Color.white.opacity(
                                0.78
                            ),
                            lineWidth: 1
                        )
                    }
                    .shadow(
                        color:
                            .black.opacity(0.12),
                        radius: 10,
                        y: 4
                    )
                }
                .accessibilityLabel(
                    "Filter and sort routes"
                )
            }

            if visibleRegion != nil {
                Button {
                    Task {
                        await searchVisibleArea()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSearchingVisibleArea {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(
                                systemName:
                                    "magnifyingglass"
                            )
                        }

                        Text("Search this area")
                    }
                    .font(
                        .subheadline.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .padding(.horizontal, 17)
                    .frame(height: 42)
                    .background(
                        .ultraThinMaterial,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                Color.white.opacity(
                                    0.76
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color:
                            .black.opacity(0.12),
                        radius: 10,
                        y: 4
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSearchingVisibleArea)
            }

            exploreTrailStatusOverlay
        }
        .padding(.horizontal, 12)
        .safeAreaPadding(
            .top,
            embeddedInTab ? 8 : 0
        )
    }

    @ViewBuilder
    private var exploreTrailStatusOverlay:
        some View {
        if (
            publicTrailDiscovery.isLoading ||
            publicTrailDiscovery.isWarmingCache
           ) &&
           publicTrailDiscovery.trails.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text(
                    publicTrailDiscovery
                        .isWarmingCache
                        ? "Finding public trails nearby…"
                        : "Loading public trails…"
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                .ultraThinMaterial,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        Color.white.opacity(0.68),
                        lineWidth: 1
                    )
            }
        } else if let publicTrailError =
                    publicTrailDiscovery
                        .errorMessage,
                  publicTrailDiscovery
                    .trails.isEmpty {
            HStack(spacing: 7) {
                Image(
                    systemName:
                        "exclamationmark.triangle"
                )
                Text(publicTrailError)
                    .lineLimit(2)
            }
            .font(.caption)
            .foregroundStyle(
                ATHLTHTheme.primaryText
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                .ultraThinMaterial,
                in:
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
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
        guard filter == .all || filter == .routes else {
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
            .prefix(35)
            .compactMap {
                route ->
                    (TrainingRoute, CLLocationDistance)?
                in
                guard !route.coordinates.isEmpty
                else {
                    return nil
                }

                guard let nearest =
                    route.hitTestLocations
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
        let saved = isRouteSaved(route)
        let creator = creatorProfile(for: route)

        return VStack(
            alignment: .leading,
            spacing: 11
        ) {
            HStack(
                alignment: .top,
                spacing: 11
            ) {
                creatorAvatar(
                    route: route,
                    profile: creator
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
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

                HStack(spacing: 7) {
                    if route.ownerID !=
                        session.profile.userID {
                        Button {
                            toggleSavedRoute(
                                route
                            )
                        } label: {
                            Image(
                                systemName:
                                    saved
                                        ? "bookmark.fill"
                                        : "bookmark"
                            )
                            .font(
                                .system(
                                    size: 12,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                saved
                                    ? ATHLTHTheme.vitality
                                    : ATHLTHTheme.accentDeep
                            )
                            .frame(
                                width: 30,
                                height: 30
                            )
                            .background(
                                Color.white.opacity(0.48),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color.white.opacity(0.68),
                                        lineWidth: 0.7
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            saved
                                ? "Remove saved route"
                                : "Save route"
                        )
                    }

                    Button {
                        withAnimation(
                            .easeInOut(
                                duration: 0.18
                            )
                        ) {
                            selectedRoute = nil
                        }
                    } label: {
                        Image(
                            systemName: "xmark"
                        )
                        .font(
                            .system(
                                size: 10,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .frame(
                            width: 30,
                            height: 30
                        )
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
                        icon:
                            "mountain.2.fill"
                    )
                }

                if let distance =
                    distanceToRouteStart(route) {
                    previewMetric(
                        value: distance,
                        icon: "location.fill"
                    )
                }

                if !isPublicTrailRoute(route) {
                    previewMetric(
                        value:
                            "\(previewAttemptCount(for: route))",
                        icon:
                            "arrow.trianglehead.2.clockwise.rotate.90"
                    )
                }
            }

            if isPublicTrailRoute(route) {
                Text(
                    publicTrailDiscovery
                        .attribution
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)
                .padding(.horizontal, 2)
            }

            if previewLeaderboardIsLoading(
                for: route
            ) &&
                topThree.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Loading leaderboard…",
                            norwegian:
                                "Laster toppliste…"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                    Spacer()
                }
                .frame(height: 52)
                .padding(.horizontal, 12)
                .background(
                    Color.white.opacity(0.42),
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )
            } else if !topThree.isEmpty {
                HStack(spacing: 10) {
                    Image(
                        systemName:
                            "trophy.fill"
                    )
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.premiumGold
                    )
                    .frame(
                        width: 36,
                        height: 36
                    )
                    .background(
                        ATHLTHTheme
                            .champagneSoft
                            .opacity(0.82),
                        in: Circle()
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Leaderboard",
                                norwegian:
                                    "Toppliste"
                            )
                        )
                        .font(
                            .caption.weight(
                                .bold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                        Text(
                            compactLeaderboardSummary(
                                topThree
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    }

                    Spacer(
                        minLength: 4
                    )

                    NavigationLink {
                        RouteDetailView(
                            route: route
                        )
                    } label: {
                        HStack(spacing: 4) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "See all",
                                    norwegian:
                                        "Se alle"
                                )
                            )

                            Image(
                                systemName:
                                    "chevron.right"
                            )
                        }
                        .font(
                            .caption.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 11)
                .frame(height: 56)
                .background(
                    Color.white.opacity(0.52),
                    in: RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                    .stroke(
                        Color.white.opacity(0.72),
                        lineWidth: 0.8
                    )
                }
            } else {
                HStack(spacing: 8) {
                    Image(
                        systemName:
                            "trophy"
                    )
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "No qualifying times yet",
                            norwegian:
                                "Ingen kvalifiserende tider ennå"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                    Spacer()
                }
                .frame(height: 48)
                .padding(.horizontal, 12)
                .background(
                    Color.white.opacity(0.34),
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )
            }

            HStack(spacing: 8) {
                if isPublicTrailRoute(route) {
                    Button {
                        routeToStart = route
                    } label: {
                        routePreviewActionLabel(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Start",
                                    norwegian: "Start"
                                ),
                            icon: "play.fill"
                        )
                    }
                    .buttonStyle(.plain)
                } else if settings
                    .trainingDeviceProvider ==
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
                                .frame(height: 42)
                                .background(
                                    Color.white
                                        .opacity(0.48),
                                    in:
                                        RoundedRectangle(
                                            cornerRadius:
                                                14,
                                            style:
                                                .continuous
                                        )
                                )
                        } else {
                            routePreviewActionLabel(
                                title:
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Start",
                                        norwegian:
                                            "Start"
                                    ),
                                icon:
                                    "play.fill"
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        startingRoute ||
                        !watchConnection.isReady
                    )
                }

                NavigationLink {
                    RouteDetailView(
                        route: route
                    )
                } label: {
                    routePreviewActionLabel(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Details",
                                norwegian:
                                    "Detaljer"
                            ),
                        icon:
                            "chevron.right",
                        iconTrailing: true
                    )
                }
                .buttonStyle(.plain)
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

    private func routePreviewActionLabel(
        title: String,
        icon: String,
        iconTrailing: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            if !iconTrailing {
                Image(
                    systemName: icon
                )
            }

            Text(title)

            if iconTrailing {
                Image(
                    systemName: icon
                )
            }
        }
        .font(
            .caption.weight(.semibold)
        )
        .foregroundStyle(
            ATHLTHTheme.primaryText
                .opacity(0.82)
        )
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(
            Color.white.opacity(0.48),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.68),
                lineWidth: 0.8
            )
        }
    }

    private func toggleSavedRoute(
        _ route: TrainingRoute
    ) {
        if isRouteSaved(route) {
            if let savedRoute =
                savedRouteCopy(
                    for: route
                ) {
                session.deleteSavedRoute(
                    savedRoute.id
                )
                routeActionMessage =
                    "Route removed from My Routes."
            }
        } else {
            session.saveSharedRoute(
                route,
                sourceOwnerID:
                    route.ownerID,
                sourceRouteID:
                    route.id
            )
            routeActionMessage =
                "Route saved to My Routes."
        }
    }

    private func publicTrailID(
        for route: TrainingRoute
    ) -> UUID {
        route.sharedSourceRouteID ??
            route.id
    }

    private func previewLeaderboardIsLoading(
        for route: TrainingRoute
    ) -> Bool {
        if isPublicTrailRoute(route) {
            let trailID =
                publicTrailID(
                    for: route
                )
            return publicTrailAttempts
                .isLoading &&
                publicTrailAttempts
                    .loadedTrailID !=
                    trailID
        }

        return routeAttempts.isLoading &&
            routeAttempts.loadedRouteID !=
                route.id
    }

    private func compactLeaderboardSummary(
        _ attempts: [RouteAttemptRecord]
    ) -> String {
        attempts
            .enumerated()
            .map { index, attempt in
                "\(index + 1). " +
                compactAthleteName(
                    attempt
                ) +
                " " +
                routeClock(
                    attempt
                        .durationSeconds
                )
            }
            .joined(
                separator: "  ·  "
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
        if isPublicTrailRoute(route) {
            Circle()
                .fill(
                    ATHLTHTheme.vitalitySoft
                )
                .overlay {
                    Image(
                        systemName: "map.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )
                }
                .frame(
                    width: 38,
                    height: 38
                )
        } else if let url = creatorAvatarURL(
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
        if isPublicTrailRoute(route) {
            if route.routeSource ==
                "kartverket_turrutebasen" {
                return "Public Trail · Kartverket"
            }

            return "Public Trail · OpenStreetMap"
        }

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

    private func isPublicTrailRoute(
        _ route: TrainingRoute
    ) -> Bool {
        route.routeSource == "openstreetmap" ||
        route.routeSource == "kartverket_turrutebasen" ||
        route.ownerID ==
            PublicTrailRecord
                .publicSourceOwnerID ||
        route.sharedSourceOwnerID ==
            PublicTrailRecord
                .publicSourceOwnerID
    }

    private func previewLeaderboard(
        for route: TrainingRoute
    ) -> [RouteAttemptRecord] {
        if isPublicTrailRoute(route) {
            let trailID =
                publicTrailID(
                    for: route
                )

            guard publicTrailAttempts
                .loadedTrailID == trailID,
                  publicTrailAttempts
                    .leaderboardEnabled
            else {
                return []
            }

            return publicTrailAttempts
                .leaderboard()
        }

        guard routeAttempts
            .loadedRouteID == route.id
        else {
            return []
        }

        return routeAttempts
            .leaderboard()
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

    private func savedRouteCopy(
        for route: TrainingRoute
    ) -> TrainingRoute? {
        session.savedRoutes.first {
            $0.id == route.id ||
            $0.sharedSourceRouteID == route.id
        }
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

    private func launchRunFromExplore(
        _ configuration: RunQuickStartConfiguration
    ) {
        Task { @MainActor in
            await social.beginWorkoutWithFriends(
                title: configuration.title,
                kind: .running,
                friends: configuration.friends,
                creatorName: session.profile.displayName,
                creatorUsername: session.profile.username
            )

            do {
                try await WorkoutLaunchCoordinator
                    .startRunQuick(
                        configuration: configuration,
                        session: session,
                        settings: settings,
                        gear: gear,
                        phoneWorkout: phoneWorkout,
                        watchConnection:
                            watchConnection,
                        spotify: spotify,
                        ghostRace: ghostRace
                    )

                routeActionMessage =
                    "\(configuration.title) started" +
                    (
                        configuration.captureDevice ==
                            .appleWatch
                            ? " on Apple Watch."
                            : " on iPhone."
                    )
            } catch {
                await social.cancelActiveWorkout()
                routeActionError =
                    error.localizedDescription
            }
        }
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

            watchConnection.sendRunningWorkout(
                WatchRunningWorkoutTransfer(
                    title: route.title,
                    steps: [],
                    routeAlerts:
                        settings.routeAlertConfiguration
                )
            )

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

        for trail in publicTrailDiscovery.trails {
            let route = trail.trainingRoute

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
                    isMine: false,
                    isPublicTrail: true,
                    trainingRoute: route
                )
        }

        let values =
            Array(routesByID.values)
                .filter {
                    routeLengthFilter.matches(
                        $0.distanceKilometers
                    )
                }

        guard let location =
                activeSearchCenter ??
                locationStore.location
        else {
            return values.sorted {
                routeSort == .longest
                    ? $0.distanceKilometers >
                        $1.distanceKilometers
                    : $0.distanceKilometers <
                        $1.distanceKilometers
            }
        }

        let candidates =
            values.compactMap {
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

                if !route.isPublicTrail,
                   distance > 50_000 {
                    return nil
                }

                return (route, distance)
            }

        return candidates
            .sorted { lhs, rhs in
                switch routeSort {
                case .nearest:
                    return lhs.1 < rhs.1
                case .shortest:
                    return lhs.0.distanceKilometers <
                        rhs.0.distanceKilometers
                case .longest:
                    return lhs.0.distanceKilometers >
                        rhs.0.distanceKilometers
                }
            }
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
                activeSearchCenter ??
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

    private var nearbyChallenges: [ATHLTHChallenge] {
        let currentUserID = session.profile.userID

        let candidates = challenges.visibleChallenges.filter { challenge in
            challenge.status != .cancelled &&
            (
                challenge.visibility == .publicProfile ||
                challenge.creatorID == currentUserID ||
                challenge.participants.contains {
                    $0.userID == currentUserID
                }
            )
        }

        guard let location = locationStore.location else {
            return candidates.filter {
                challengeCoordinate($0) != nil
            }
        }

        return candidates
            .compactMap {
                challenge ->
                    (ATHLTHChallenge, CLLocationDistance)?
                in
                guard let coordinate =
                        challengeCoordinate(challenge)
                else {
                    return nil
                }

                let distance = CLLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
                .distance(from: location)

                guard distance <= 50_000 else {
                    return nil
                }

                return (challenge, distance)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private func challengeCoordinate(
        _ challenge: ATHLTHChallenge
    ) -> CLLocationCoordinate2D? {
        if let meetup = challenge.rules.meetup {
            return CLLocationCoordinate2D(
                latitude: meetup.latitude,
                longitude: meetup.longitude
            )
        }

        guard let coordinates =
                challenge.rules.route?.coordinates,
              !coordinates.isEmpty
        else {
            return nil
        }

        let latitude =
            coordinates.reduce(0) {
                $0 + $1.latitude
            } / Double(coordinates.count)
        let longitude =
            coordinates.reduce(0) {
                $0 + $1.longitude
            } / Double(coordinates.count)

        return CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
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

    @MainActor
    private func searchVisibleArea() async {
        guard let visibleRegion else {
            return
        }

        isSearchingVisibleArea = true
        defer {
            isSearchingVisibleArea = false
        }

        activeSearchCenter = CLLocation(
            latitude: visibleRegion.center.latitude,
            longitude: visibleRegion.center.longitude
        )

        withAnimation(.easeInOut(duration: 0.16)) {
            selectedRoute = nil
        }

        await publicTrailDiscovery.refresh(
            in: visibleRegion,
            force: true
        )

        shouldSearchVisibleArea = false
    }

    private func centerOnUser() {
        guard let location =
                locationStore.location
        else {
            return
        }

        let coordinate = location.coordinate
        activeSearchCenter = location
        shouldSearchVisibleArea = false
        suppressNextSearchPrompt = true
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
