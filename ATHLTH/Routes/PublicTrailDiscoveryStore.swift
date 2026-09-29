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

private struct PublicTrailDiscoveryRequest:
    Encodable {
    let latitude: Double
    let longitude: Double
    let radiusKilometers: Double
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
        try await client.functions.invoke(
            "discover-public-trails",
            options:
                FunctionInvokeOptions(
                    body:
                        PublicTrailDiscoveryRequest(
                            latitude:
                                location.coordinate
                                    .latitude,
                            longitude:
                                location.coordinate
                                    .longitude,
                            radiusKilometers:
                                radiusKilometers
                        )
                )
        )
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
                        )
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
                            )
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
