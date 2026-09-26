import CoreLocation
import Foundation
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

final class SupabaseRouteDiscoveryService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func loadDiscoverableRoutes() async throws -> [CommunityRouteRecord] {
        // RLS decides which routes the signed-in user may see:
        // public, friends-only where a friendship exists, plus own routes.
        try await client
            .from("community_routes")
            .select()
            .order("created_at", ascending: false)
            .limit(250)
            .execute()
            .value
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
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service: SupabaseRouteDiscoveryService

    init(
        service: SupabaseRouteDiscoveryService =
            SupabaseRouteDiscoveryService()
    ) {
        self.service = service
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            routes = try await service.loadDiscoverableRoutes()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func publish(_ route: TrainingRoute) async {
        do {
            try await service.publish(route)
            await refresh()
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
