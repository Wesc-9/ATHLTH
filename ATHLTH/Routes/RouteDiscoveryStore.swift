import CoreLocation
import Foundation
import MapKit
import Supabase

struct CommunityRouteRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let ownerID: UUID
    let title: String
    let visibility: ProfileVisibility
    let coordinates: [RouteCoordinate]
    let distanceKilometers: Double
    let elevationGainMeters: Double?
    let startName: String?
    let endName: String?
    let expectedTravelTimeSeconds: TimeInterval?
    let routeSource: String?
    let centerLatitude: Double
    let centerLongitude: Double
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case title
        case visibility
        case coordinates
        case distanceKilometers = "distance_kilometers"
        case elevationGainMeters = "elevation_gain_meters"
        case startName = "start_name"
        case endName = "end_name"
        case expectedTravelTimeSeconds = "expected_travel_time_seconds"
        case routeSource = "route_source"
        case centerLatitude = "center_latitude"
        case centerLongitude = "center_longitude"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var centerCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: centerLatitude,
            longitude: centerLongitude
        )
    }

    var trainingRoute: TrainingRoute {
        TrainingRoute(
            id: id,
            ownerID: ownerID,
            title: title,
            visibility: visibility,
            coordinates: coordinates,
            distanceKilometers: distanceKilometers,
            elevationGainMeters: elevationGainMeters,
            importedFilename: nil,
            createdAt: createdAt,
            startName: startName,
            endName: endName,
            expectedTravelTimeSeconds: expectedTravelTimeSeconds,
            routeSource: routeSource
        )
    }
}

/// A bounded local lookup prevents the global newest-routes page from
/// crowding older routes out of the Explore map in a particular city.
struct RouteDiscoveryNearbyBounds {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double?
    let maxLongitude: Double?

    init?(coordinate: CLLocationCoordinate2D, radiusKilometers: Double) {
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              radiusKilometers.isFinite,
              radiusKilometers > 0 else { return nil }

        let latitudeDelta = radiusKilometers / 111.2
        let latitudeRadians = coordinate.latitude * .pi / 180
        let longitudeDelta = radiusKilometers /
            (111.2 * max(0.01, abs(cos(latitudeRadians))))
        minLatitude = max(-90, coordinate.latitude - latitudeDelta)
        maxLatitude = min(90, coordinate.latitude + latitudeDelta)

        // Near the dateline/poles the longitude range wraps. Use the
        // latitude-only server filter and exact distance check locally.
        if longitudeDelta >= 180 ||
            coordinate.longitude - longitudeDelta < -180 ||
            coordinate.longitude + longitudeDelta > 180 {
            minLongitude = nil
            maxLongitude = nil
        } else {
            minLongitude = coordinate.longitude - longitudeDelta
            maxLongitude = coordinate.longitude + longitudeDelta
        }
    }
}

/// The exact visible viewport is the source of truth for Explore searches.
/// Bounds are intentionally not tied to the user's GPS position.
struct RouteDiscoveryRegionBounds {
    let center: CLLocationCoordinate2D
    let latitudeSpan: Double
    let longitudeSpan: Double
    let south: Double
    let north: Double
    let west: Double?
    let east: Double?

    init?(region: MKCoordinateRegion) {
        let latitude = region.center.latitude
        let longitude = region.center.longitude
        let latDelta = region.span.latitudeDelta
        let lonDelta = region.span.longitudeDelta
        guard CLLocationCoordinate2DIsValid(region.center),
              latDelta.isFinite, lonDelta.isFinite,
              latDelta > 0, lonDelta > 0 else { return nil }

        center = region.center
        latitudeSpan = latDelta
        longitudeSpan = lonDelta
        south = max(-90, latitude - latDelta / 2)
        north = min(90, latitude + latDelta / 2)
        if lonDelta >= 360 ||
            longitude - lonDelta / 2 < -180 ||
            longitude + lonDelta / 2 > 180 {
            west = nil
            east = nil
        } else {
            west = longitude - lonDelta / 2
            east = longitude + lonDelta / 2
        }
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        guard latitude.isFinite, longitude.isFinite,
              latitude >= south, latitude <= north else { return false }
        if longitudeSpan >= 360 { return true }
        let delta = abs(
            (longitude - center.longitude + 540)
                .truncatingRemainder(dividingBy: 360) - 180
        )
        return delta <= longitudeSpan / 2
    }
}

private struct CommunityRouteWrite: Encodable {
    let id: UUID
    let ownerID: UUID
    let title: String
    let visibility: ProfileVisibility
    let coordinates: [RouteCoordinate]
    let distanceKilometers: Double
    let elevationGainMeters: Double?
    let startName: String?
    let endName: String?
    let expectedTravelTimeSeconds: TimeInterval?
    let routeSource: String?
    let centerLatitude: Double
    let centerLongitude: Double
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case title
        case visibility
        case coordinates
        case distanceKilometers = "distance_kilometers"
        case elevationGainMeters = "elevation_gain_meters"
        case startName = "start_name"
        case endName = "end_name"
        case expectedTravelTimeSeconds = "expected_travel_time_seconds"
        case routeSource = "route_source"
        case centerLatitude = "center_latitude"
        case centerLongitude = "center_longitude"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

@MainActor
final class SupabaseRouteDiscoveryService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func loadDiscoverableRoutes(
        limit: Int = 48
    ) async throws -> [CommunityRouteRecord] {
        // Community surfaces only need a bounded discovery window. Keeping
        // hundreds of full GPS polylines resident at once creates avoidable
        // JSON, memory and MapKit pressure. Full owned routes remain stored
        // separately in AppSessionStore.
        try await client
            .from("community_routes")
            .select()
            .order("created_at", ascending: false)
            .limit(min(max(limit, 12), 80))
            .execute()
            .value
    }

    func loadDiscoverableRoutes(
        near location: CLLocation,
        radiusKilometers: Double = 50,
        limit: Int = 80
    ) async throws -> [CommunityRouteRecord] {
        guard let bounds = RouteDiscoveryNearbyBounds(
            coordinate: location.coordinate,
            radiusKilometers: radiusKilometers
        ) else { return [] }

        var query = client.from("community_routes")
            .select()
            .gte("center_latitude", value: bounds.minLatitude)
            .lte("center_latitude", value: bounds.maxLatitude)

        if let west = bounds.minLongitude,
           let east = bounds.maxLongitude {
            query = query.gte("center_longitude", value: west)
                .lte("center_longitude", value: east)
        }

        let candidates: [CommunityRouteRecord] = try await query
            .order("created_at", ascending: false)
            .limit(min(max(limit, 12), 100))
            .execute()
            .value

        let maxDistance = radiusKilometers * 1_000
        return candidates.filter { route in
            CLLocation(
                latitude: route.centerLatitude,
                longitude: route.centerLongitude
            ).distance(from: location) <= maxDistance
        }
    }

    func loadDiscoverableRoutes(
        in region: MKCoordinateRegion,
        limit: Int = 100
    ) async throws -> [CommunityRouteRecord] {
        guard let bounds = RouteDiscoveryRegionBounds(region: region)
        else { return [] }

        var query = client.from("community_routes")
            .select()
            .gte("center_latitude", value: bounds.south)
            .lte("center_latitude", value: bounds.north)

        if let west = bounds.west, let east = bounds.east {
            query = query.gte("center_longitude", value: west)
                .lte("center_longitude", value: east)
        }

        let candidates: [CommunityRouteRecord] = try await query
            .order("created_at", ascending: false)
            .limit(min(max(limit, 12), 100))
            .execute()
            .value
        return candidates.filter {
            bounds.contains(
                latitude: $0.centerLatitude,
                longitude: $0.centerLongitude
            )
        }
    }

    func searchRoutes(
        _ query: String,
        limit: Int = 24
    ) async throws -> [CommunityRouteRecord] {
        let clean = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard clean.count >= 2 else { return [] }

        let boundedLimit = min(max(limit, 8), 40)
        let pattern = "%\(clean)%"

        async let titleRows: [CommunityRouteRecord] = client
            .from("community_routes")
            .select()
            .ilike("title", pattern: pattern)
            .limit(boundedLimit)
            .execute()
            .value

        async let startRows: [CommunityRouteRecord] = client
            .from("community_routes")
            .select()
            .ilike("start_name", pattern: pattern)
            .limit(boundedLimit)
            .execute()
            .value

        async let endRows: [CommunityRouteRecord] = client
            .from("community_routes")
            .select()
            .ilike("end_name", pattern: pattern)
            .limit(boundedLimit)
            .execute()
            .value

        let (titles, starts, ends) = try await (
            titleRows,
            startRows,
            endRows
        )
        let rows = titles + starts + ends
        var seen = Set<UUID>()

        return rows
            .filter { seen.insert($0.id).inserted }
            .prefix(boundedLimit)
            .map { $0 }
    }

    func publish(_ route: TrainingRoute) async throws {
        guard let center = route.discoveryCenterCoordinate else {
            return
        }

        let payload = CommunityRouteWrite(
            id: route.id,
            ownerID: route.ownerID,
            title: route.title,
            visibility: route.visibility,
            coordinates: route.coordinates,
            distanceKilometers: route.distanceKilometers,
            elevationGainMeters: route.elevationGainMeters,
            startName: route.startName,
            endName: route.endName,
            expectedTravelTimeSeconds: route.expectedTravelTimeSeconds,
            routeSource: route.routeSource,
            centerLatitude: center.latitude,
            centerLongitude: center.longitude,
            createdAt: route.createdAt,
            updatedAt: Date()
        )

        try await client
            .from("community_routes")
            .upsert(payload, onConflict: "id")
            .execute()
    }

    func remove(routeID: UUID) async throws {
        try await client
            .from("community_routes")
            .delete()
            .eq("id", value: routeID)
            .execute()
    }
}

@MainActor
final class RouteDiscoveryStore: ObservableObject {
    @Published private(set) var routes: [CommunityRouteRecord] = []
    /// Explore-specific geographic page, independent of other route lists.
    @Published private(set) var localRoutes: [CommunityRouteRecord] = []
    @Published private(set) var searchResults: [CommunityRouteRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingNearby = false
    @Published var errorMessage: String?

    private let service: SupabaseRouteDiscoveryService
    private var lastRefreshAt: Date?
    private var lastNearbyRefreshAt: Date?
    private var lastNearbyCenter: CLLocation?

    init(
        service: SupabaseRouteDiscoveryService =
            SupabaseRouteDiscoveryService()
    ) {
        self.service = service
    }

    func refresh(force: Bool = false) async {
        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < 180,
           !routes.isEmpty {
            return
        }

        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedRoutes = try await service.loadDiscoverableRoutes()

            guard !Task.isCancelled else { return }

            routes = loadedRoutes
            lastRefreshAt = Date()
            errorMessage = nil
        } catch is CancellationError {
            // Pull-to-refresh and SwiftUI view tasks may legitimately
            // cancel an in-flight discovery request. Do not surface
            // cancellation as a user-facing Community error.
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func refreshNearby(
        near location: CLLocation,
        radiusKilometers: Double = 50,
        force: Bool = false
    ) async {
        guard CLLocationCoordinate2DIsValid(location.coordinate),
              radiusKilometers.isFinite, radiusKilometers > 0 else { return }

        if !force,
           let lastNearbyRefreshAt,
           let lastNearbyCenter,
           Date().timeIntervalSince(lastNearbyRefreshAt) < 180,
           location.distance(from: lastNearbyCenter) < 1_500 {
            return
        }

        if isLoadingNearby {
            // A tab switch can cancel one view task while the next starts.
            // Do not discard the new tab's initial request as a duplicate.
            for _ in 0..<80 {
                guard !Task.isCancelled else { return }
                guard isLoadingNearby else { break }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch { return }
            }
            guard !isLoadingNearby, !Task.isCancelled else { return }
            if !force,
               !localRoutes.isEmpty,
               let lastNearbyRefreshAt,
               let lastNearbyCenter,
               Date().timeIntervalSince(lastNearbyRefreshAt) < 180,
               location.distance(from: lastNearbyCenter) < 1_500 {
                return
            }
        }
        isLoadingNearby = true
        defer { isLoadingNearby = false }

        do {
            let found = try await service.loadDiscoverableRoutes(
                near: location,
                radiusKilometers: radiusKilometers
            )
            guard !Task.isCancelled else { return }
            localRoutes = found
            lastNearbyCenter = location
            lastNearbyRefreshAt = Date()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if localRoutes.isEmpty && routes.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Replace the Explore viewport result rather than appending all previous
    /// areas. Other screens keep their existing global route catalogue.
    func refreshVisibleRegion(
        _ region: MKCoordinateRegion
    ) async {
        guard RouteDiscoveryRegionBounds(region: region) != nil else { return }
        if isLoadingNearby {
            // A legacy location query started before the map appeared
            // should never make the explicit viewport search a no-op.
            for _ in 0..<100 {
                if !isLoadingNearby || Task.isCancelled { break }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch { return }
            }
            guard !isLoadingNearby, !Task.isCancelled else { return }
        }
        isLoadingNearby = true
        defer { isLoadingNearby = false }

        do {
            let found = try await service.loadDiscoverableRoutes(in: region)
            guard !Task.isCancelled else { return }
            localRoutes = found
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            localRoutes = []
            errorMessage = error.localizedDescription
        }
    }

    func search(_ query: String) async {
        let requestedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard requestedQuery.count >= 2 else {
            searchResults = []
            return
        }

        do {
            let results = try await service.searchRoutes(requestedQuery)
            guard !Task.isCancelled else { return }
            searchResults = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
        }
    }

    func clearSearch() {
        searchResults = []
    }

    func publish(_ route: TrainingRoute) async {
        do {
            try await service.publish(route)
            await refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(routeID: UUID) async {
        do {
            try await service.remove(routeID: routeID)
            routes.removeAll { $0.id == routeID }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncOwnedPublicRoutes(
        _ ownedRoutes: [TrainingRoute]
    ) async {
        do {
            for route in ownedRoutes {
                try await service.publish(route)
            }

            self.routes = try await service.loadDiscoverableRoutes()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func nearbyRoutes(
        from location: CLLocation,
        radiusKilometers: Double = 35
    ) -> [CommunityRouteRecord] {
        let radiusMeters = radiusKilometers * 1_000

        return routes
            .filter { route in
                CLLocation(
                    latitude: route.centerLatitude,
                    longitude: route.centerLongitude
                )
                .distance(from: location) <= radiusMeters
            }
            .sorted { lhs, rhs in
                let lhsDistance = CLLocation(
                    latitude: lhs.centerLatitude,
                    longitude: lhs.centerLongitude
                )
                .distance(from: location)

                let rhsDistance = CLLocation(
                    latitude: rhs.centerLatitude,
                    longitude: rhs.centerLongitude
                )
                .distance(from: location)

                return lhsDistance < rhsDistance
            }
    }
}

extension TrainingRoute {
    var discoveryCenterCoordinate: CLLocationCoordinate2D? {
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
