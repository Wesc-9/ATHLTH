import CoreLocation
import Foundation
import MapKit
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
    var routeShape: String? = nil
    var surfaceSummary: String? = nil
    var difficulty: String? = nil
    var osmDescription: String? = nil
    var website: String? = nil
    var estimatedRunSeconds: TimeInterval? = nil
    var estimatedWalkSeconds: TimeInterval? = nil
    var elevationGainMeters: Double? = nil
    var elevationLossMeters: Double? = nil
    var minElevationMeters: Double? = nil
    var maxElevationMeters: Double? = nil
    var averageGradePercent: Double? = nil
    var maxGradePercent: Double? = nil
    var elevationProfile: [Double]? = nil

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
        case routeShape = "route_shape"
        case surfaceSummary = "surface_summary"
        case difficulty
        case osmDescription = "osm_description"
        case website
        case estimatedRunSeconds = "estimated_run_seconds"
        case estimatedWalkSeconds = "estimated_walk_seconds"
        case elevationGainMeters = "elevation_gain_meters"
        case elevationLossMeters = "elevation_loss_meters"
        case minElevationMeters = "min_elevation_meters"
        case maxElevationMeters = "max_elevation_meters"
        case averageGradePercent = "average_grade_percent"
        case maxGradePercent = "max_grade_percent"
        case elevationProfile = "elevation_profile"
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
            elevationGainMeters: elevationGainMeters,
            importedFilename: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            startName: reference,
            endName: nil,
            expectedTravelTimeSeconds: estimatedRunSeconds,
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

    private struct DiscoverParams: Encodable {
        let latitude: Double
        let longitude: Double
        let radiusKilometers: Double
        let forceRefresh: Bool
    }

    func discover(
        near location: CLLocation,
        radiusKilometers: Double,
        forceRefresh: Bool = false
    ) async throws ->
        PublicTrailDiscoveryResponse {
        let response:
            PublicTrailDiscoveryResponse =
                try await client.functions.invoke(
                    "discover-public-trails",
                    options:
                        FunctionInvokeOptions(
                            body: DiscoverParams(
                                latitude:
                                    location.coordinate
                                        .latitude,
                                longitude:
                                    location.coordinate
                                        .longitude,
                                radiusKilometers:
                                    radiusKilometers,
                                forceRefresh:
                                    forceRefresh
                            )
                        )
                )

        return response
    }
    private struct SimilarParams: Encodable {
        let p_trail_id: UUID
        let p_limit: Int
    }

    func similar(
        to trailID: UUID,
        limit: Int = 10
    ) async throws -> [PublicTrailRecord] {
        let params = SimilarParams(
            p_trail_id: trailID,
            p_limit: min(max(limit, 1), 10)
        )

        let rows: [PublicTrailRecord] =
            try await client
                .rpc(
                    "similar_public_trails",
                    params: params
                )
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
        errorMessage = nil
        defer {
            isLoading = false
        }

        do {
            var response =
                try await service.discover(
                    near: location,
                    radiusKilometers:
                        min(
                            max(
                                radiusKilometers,
                                3
                            ),
                            20
                        ),
                    forceRefresh: force
                )

            guard !Task.isCancelled else {
                return
            }

            apply(
                response,
                center: location
            )

            // A cold cell returns immediately while the Edge Function warms
            // the OpenStreetMap cache in the background. Retry exactly once
            // so first-time Explore users usually see routes without having
            // to close and reopen the screen.
            if response.trails.isEmpty,
               response.isRefreshing {
                isWarmingCache = true

                try await Task.sleep(
                    for: .seconds(4)
                )

                guard !Task.isCancelled else {
                    return
                }

                response =
                    try await service.discover(
                        near: location,
                        radiusKilometers:
                            min(
                                max(
                                    radiusKilometers,
                                    3
                                ),
                                20
                            ),
                        forceRefresh: true
                    )

                guard !Task.isCancelled else {
                    return
                }

                apply(
                    response,
                    center: location
                )
            }

            isWarmingCache =
                response.isRefreshing &&
                response.trails.isEmpty
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }

            // Preserve already-discovered routes when a refresh fails.
            if trails.isEmpty {
                errorMessage =
                    "Public trails are temporarily unavailable."
            }
            isWarmingCache = false
        }
    }

    func refresh(
        in region: MKCoordinateRegion,
        force: Bool = true
    ) async {
        guard region.center.latitude.isFinite,
              region.center.longitude.isFinite,
              region.span.latitudeDelta.isFinite,
              region.span.longitudeDelta.isFinite
        else {
            return
        }

        let center = CLLocation(
            latitude: region.center.latitude,
            longitude: region.center.longitude
        )
        let corner = CLLocation(
            latitude:
                region.center.latitude +
                region.span.latitudeDelta / 2,
            longitude:
                region.center.longitude +
                region.span.longitudeDelta / 2
        )
        let radiusKilometers =
            min(
                max(
                    center.distance(from: corner) / 1_000,
                    3
                ),
                20
            )

        await refresh(
            near: center,
            radiusKilometers: radiusKilometers,
            force: force
        )
    }

    func similar(
        to trailID: UUID,
        limit: Int = 10
    ) async -> [PublicTrailRecord] {
        do {
            return try await service.similar(
                to: trailID,
                limit: limit
            )
        } catch is CancellationError {
            return []
        } catch {
            return []
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

        trails = usable

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
