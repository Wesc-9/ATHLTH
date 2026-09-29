import CoreLocation
import Foundation
import Supabase

struct PublicTrailRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let osmRelationID: Int64
    let name: String
    let routeKind: String
    let network: String?
    let reference: String?
    let operatorName: String?
    let symbol: String?
    let coordinates: [RouteCoordinate]
    let distanceKilometers: Double
    let centerLatitude: Double
    let centerLongitude: Double
    let leaderboardEnabled: Bool
    let athlthVerified: Bool
    let source: String

    enum CodingKeys: String, CodingKey {
        case id
        case osmRelationID = "osm_relation_id"
        case name
        case routeKind = "route_kind"
        case network
        case reference
        case operatorName = "operator_name"
        case symbol
        case coordinates
        case distanceKilometers = "distance_kilometers"
        case centerLatitude = "center_latitude"
        case centerLongitude = "center_longitude"
        case leaderboardEnabled = "leaderboard_enabled"
        case athlthVerified = "athlth_verified"
        case source
    }

    static let publicSourceOwnerID =
        UUID(
            uuidString:
                "00000000-0000-0000-0000-000000000001"
        )!

    var centerCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: centerLatitude,
            longitude: centerLongitude
        )
    }

    var trainingRoute: TrainingRoute {
        TrainingRoute(
            id: id,
            ownerID: Self.publicSourceOwnerID,
            title: name,
            visibility: .publicProfile,
            coordinates: coordinates,
            distanceKilometers: distanceKilometers,
            elevationGainMeters: nil,
            importedFilename: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            startName: reference,
            endName: nil,
            expectedTravelTimeSeconds: nil,
            routeSource: "openstreetmap"
        )
    }

    var isUsable: Bool {
        distanceKilometers.isFinite &&
        distanceKilometers >= 0.5 &&
        distanceKilometers <= 80 &&
        coordinates.count >= 2 &&
        CLLocationCoordinate2DIsValid(
            centerCoordinate
        ) &&
        coordinates.allSatisfy {
            $0.latitude.isFinite &&
            $0.longitude.isFinite &&
            CLLocationCoordinate2DIsValid(
                $0.coordinate
            )
        }
    }
}

struct PublicTrailDiscoveryResponse:
    Decodable {
    let trails: [PublicTrailRecord]
    let source: String
    let isRefreshing: Bool
    let refreshScheduled: Bool
    let cacheAgeSeconds: Int?
    let attribution: String
}

@MainActor
final class SupabasePublicTrailDiscoveryService {
    private let client: SupabaseClient

    init(
        client: SupabaseClient =
            SupabaseEnvironment.client
    ) {
        self.client = client
    }

    func discover(
        near location: CLLocation,
        radiusKilometers: Double
    ) async throws ->
        PublicTrailDiscoveryResponse {
        let response:
            PublicTrailDiscoveryResponse =
                try await client.functions.invoke(
                    "discover-public-trails",
                    options:
                        FunctionInvokeOptions(
                            body: [
                                "latitude":
                                    location.coordinate
                                        .latitude,
                                "longitude":
                                    location.coordinate
                                        .longitude,
                                "radiusKilometers":
                                    radiusKilometers
                            ]
                        )
                )

        return response
    }


    func cachedTrails(
        near location: CLLocation,
        radiusKilometers: Double
    ) async throws -> [PublicTrailRecord] {
        let radius =
            min(
                max(radiusKilometers, 3),
                20
            )
        let latitude =
            location.coordinate.latitude
        let longitude =
            location.coordinate.longitude
        let latitudeDelta =
            radius / 111
        let longitudeScale =
            max(
                0.2,
                cos(
                    latitude *
                    .pi / 180
                )
            )
        let longitudeDelta =
            radius /
            (111 * longitudeScale)

        let rows: [PublicTrailRecord] =
            try await client
                .from("public_trails")
                .select()
                .gte(
                    "center_latitude",
                    value:
                        latitude -
                        latitudeDelta
                )
                .lte(
                    "center_latitude",
                    value:
                        latitude +
                        latitudeDelta
                )
                .gte(
                    "center_longitude",
                    value:
                        longitude -
                        longitudeDelta
                )
                .lte(
                    "center_longitude",
                    value:
                        longitude +
                        longitudeDelta
                )
                .gte(
                    "distance_kilometers",
                    value: 0.5
                )
                .order(
                    "athlth_verified",
                    ascending: false
                )
                .order(
                    "distance_kilometers",
                    ascending: true
                )
                .limit(24)
                .execute()
                .value

        return rows.filter(\.isUsable)
    }
    func fetch(
        id: UUID
    ) async throws -> PublicTrailRecord? {
        let rows: [PublicTrailRecord] =
            try await client
                .from("public_trails")
                .select()
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value

        return rows.first
    }

}

@MainActor
final class PublicTrailDiscoveryStore:
    ObservableObject {
    @Published private(set)
    var trails: [PublicTrailRecord] = []

    @Published private(set)
    var isLoading = false

    @Published private(set)
    var isWarmingCache = false

    @Published private(set)
    var attribution =
        "© OpenStreetMap contributors"

    @Published var errorMessage: String?

    private let service:
        SupabasePublicTrailDiscoveryService

    private var lastRefreshAt: Date?
    private var lastCenter: CLLocation?

    private let refreshInterval:
        TimeInterval = 10 * 60

    private let movementThreshold:
        CLLocationDistance = 1_500

    init(
        service:
            SupabasePublicTrailDiscoveryService =
                SupabasePublicTrailDiscoveryService()
    ) {
        self.service = service
    }

    func refresh(
        near location: CLLocation,
        radiusKilometers: Double = 12,
        force: Bool = false
    ) async {
        guard CLLocationCoordinate2DIsValid(
            location.coordinate
        ),
        location.coordinate.latitude.isFinite,
        location.coordinate.longitude.isFinite
        else {
            return
        }

        if !force,
           !trails.isEmpty,
           let lastRefreshAt,
           let lastCenter,
           Date().timeIntervalSince(
                lastRefreshAt
           ) < refreshInterval,
           location.distance(
                from: lastCenter
           ) < movementThreshold {
            return
        }

        guard !isLoading else {
            return
        }

        isLoading = true
        isWarmingCache = false
        errorMessage = nil
        defer {
            isLoading = false
        }

        let radius =
            min(
                max(
                    radiusKilometers,
                    3
                ),
                20
            )

        // Supabase is the durable source shown to the user. Read the local
        // trail cache before touching the external discovery refresh so
        // Explore remains useful when OpenStreetMap/Overpass is slow or down.
        do {
            let cached =
                try await service.cachedTrails(
                    near: location,
                    radiusKilometers: radius
                )

            guard !Task.isCancelled else {
                return
            }

            if !cached.isEmpty {
                trails = cached
                lastRefreshAt = Date()
                lastCenter = location
            }
        } catch is CancellationError {
            return
        } catch {
            // A failed cache read should not prevent the refresh endpoint
            // from trying to recover the durable cache.
        }

        do {
            let response =
                try await service.discover(
                    near: location,
                    radiusKilometers: radius
                )

            guard !Task.isCancelled else {
                return
            }

            apply(
                response,
                center: location
            )

            // The backend now performs cold-cache population itself. Do not
            // hammer Overpass with an app-side four-second retry loop.
            isWarmingCache =
                response.isRefreshing &&
                trails.isEmpty

            if trails.isEmpty &&
               !response.isRefreshing {
                errorMessage =
                    "No cached public trails are available nearby yet."
            } else {
                errorMessage = nil
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }

            // If durable Supabase data was loaded, keep showing it even when
            // the external refresh endpoint is unavailable.
            if trails.isEmpty {
                errorMessage =
                    "Public trails are temporarily unavailable."
            }
            isWarmingCache = false
        }
    }

    func trail(
        id: UUID
    ) async -> PublicTrailRecord? {
        if let existing =
            trails.first(
                where: {
                    $0.id == id
                }
            ) {
            return existing
        }

        do {
            guard let resolved =
                    try await service.fetch(
                        id: id
                    ),
                  resolved.isUsable
            else {
                return nil
            }

            if !trails.contains(
                where: {
                    $0.id ==
                        resolved.id
                }
            ) {
                trails.append(resolved)
            }

            return resolved
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    func clear() {
        trails = []
        lastRefreshAt = nil
        lastCenter = nil
        errorMessage = nil
        isWarmingCache = false
    }

    private func apply(
        _ response:
            PublicTrailDiscoveryResponse,
        center: CLLocation
    ) {
        let usable =
            response.trails
                .filter(\.isUsable)

        if !usable.isEmpty ||
           trails.isEmpty {
            trails = usable
        }

        attribution =
            response.attribution
                .isEmpty
                ? "© OpenStreetMap contributors"
                : response.attribution

        lastRefreshAt = Date()
        lastCenter = center
        isWarmingCache =
            response.isRefreshing &&
            usable.isEmpty
    }
}
