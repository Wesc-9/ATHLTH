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
    let updatedAt: Date

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
        case updatedAt = "updated_at"
    }

    var centerCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: centerLatitude,
            longitude: centerLongitude
        )
    }

    var renderCoordinates: [CLLocationCoordinate2D] {
        coordinates
            .sorted { $0.sequence < $1.sequence }
            .map(\.coordinate)
    }

    var hitTestLocations: [CLLocation] {
        let values = renderCoordinates
        guard values.count > 80 else {
            return values.map {
                CLLocation(
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            }
        }

        let stride = max(values.count / 80, 1)
        return values.enumerated().compactMap { index, coordinate in
            guard index == 0 ||
                    index == values.count - 1 ||
                    index % stride == 0
            else {
                return nil
            }

            return CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
    }

    var kindTitle: String {
        routeKind == "hiking" ? "Hiking route" : "Walking route"
    }

    func trainingRoute(ownerID: UUID) -> TrainingRoute {
        TrainingRoute(
            id: id,
            ownerID: ownerID,
            title: name,
            visibility: .publicProfile,
            coordinates: coordinates,
            distanceKilometers: distanceKilometers,
            elevationGainMeters: nil,
            importedFilename: nil,
            createdAt: updatedAt,
            startName: nil,
            endName: nil,
            expectedTravelTimeSeconds: nil,
            routeSource: "openstreetmap"
        )
    }
}

private struct PublicTrailDiscoveryRequest: Encodable {
    let latitude: Double
    let longitude: Double
    let radiusKilometers: Double
}

struct PublicTrailDiscoveryResponse: Decodable {
    let trails: [PublicTrailRecord]
    let source: String
    let isRefreshing: Bool
    let refreshScheduled: Bool
    let cacheAgeSeconds: Int?
    let minimumDiscoveryKilometers: Double
    let minimumLeaderboardKilometers: Double
    let attribution: String
}

@MainActor
final class PublicTrailDiscoveryService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func discover(
        center: CLLocationCoordinate2D,
        radiusKilometers: Double
    ) async throws -> PublicTrailDiscoveryResponse {
        try await client.functions.invoke(
            "discover-public-trails",
            options: FunctionInvokeOptions(
                body: PublicTrailDiscoveryRequest(
                    latitude: center.latitude,
                    longitude: center.longitude,
                    radiusKilometers: radiusKilometers
                )
            )
        )
    }
}

@MainActor
final class PublicTrailDiscoveryStore: ObservableObject {
    @Published private(set) var trails: [PublicTrailRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isWarmingCache = false
    @Published private(set) var source = "cache"
    @Published var errorMessage: String?

    private let service: PublicTrailDiscoveryService
    private var lastCenter: CLLocation?
    private var lastRadiusKilometers: Double = 0
    private var lastRefreshAt: Date?
    private var requestID = UUID()
    private var warmupRetryTask: Task<Void, Never>?

    init(
        service: PublicTrailDiscoveryService =
            PublicTrailDiscoveryService()
    ) {
        self.service = service
    }

    func refresh(
        center: CLLocationCoordinate2D,
        radiusKilometers: Double,
        force: Bool = false
    ) async {
        await refreshInternal(
            center: center,
            radiusKilometers: radiusKilometers,
            force: force,
            warmupAttempt: 0
        )
    }

    private func refreshInternal(
        center: CLLocationCoordinate2D,
        radiusKilometers: Double,
        force: Bool,
        warmupAttempt: Int
    ) async {
        let normalizedRadius =
            min(max(radiusKilometers, 3), 20)
        let location = CLLocation(
            latitude: center.latitude,
            longitude: center.longitude
        )

        if !force,
           let lastCenter,
           let lastRefreshAt,
           location.distance(from: lastCenter) < 1_500,
           abs(normalizedRadius - lastRadiusKilometers) < 2,
           Date().timeIntervalSince(lastRefreshAt) < 120 {
            return
        }

        let newRequestID = UUID()
        requestID = newRequestID
        isLoading = true
        errorMessage = nil

        do {
            let response = try await service.discover(
                center: center,
                radiusKilometers: normalizedRadius
            )

            guard requestID == newRequestID else {
                return
            }

            trails = response.trails
                .filter { $0.distanceKilometers >= 0.5 }
                .sorted { lhs, rhs in
                    if lhs.athlthVerified != rhs.athlthVerified {
                        return lhs.athlthVerified
                    }
                    return lhs.distanceKilometers < rhs.distanceKilometers
                }

            source = response.source
            isWarmingCache =
                response.isRefreshing &&
                trails.isEmpty

            lastCenter = location
            lastRadiusKilometers = normalizedRadius
            lastRefreshAt = Date()
            isLoading = false

            if isWarmingCache,
               warmupAttempt < 3 {
                scheduleWarmupRetry(
                    center: center,
                    radiusKilometers: normalizedRadius,
                    attempt: warmupAttempt + 1
                )
            } else if !isWarmingCache {
                warmupRetryTask?.cancel()
                warmupRetryTask = nil
            }
        } catch is CancellationError {
            guard requestID == newRequestID else {
                return
            }
            isLoading = false
        } catch {
            guard requestID == newRequestID else {
                return
            }

            isLoading = false
            isWarmingCache = false

            if trails.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func scheduleWarmupRetry(
        center: CLLocationCoordinate2D,
        radiusKilometers: Double,
        attempt: Int
    ) {
        warmupRetryTask?.cancel()

        let delaySeconds =
            min(2 + (attempt * 2), 8)

        warmupRetryTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds:
                    UInt64(delaySeconds) *
                    1_000_000_000
            )

            guard !Task.isCancelled,
                  let self
            else {
                return
            }

            await self.refreshInternal(
                center: center,
                radiusKilometers: radiusKilometers,
                force: true,
                warmupAttempt: attempt
            )
        }
    }

    func nearestTrail(
        to coordinate: CLLocationCoordinate2D,
        maximumDistanceMeters: CLLocationDistance = 220
    ) -> PublicTrailRecord? {
        let target = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        return trails
            .compactMap { trail -> (PublicTrailRecord, CLLocationDistance)? in
                guard let nearest = trail.hitTestLocations
                    .lazy
                    .map({ target.distance(from: $0) })
                    .min(),
                      nearest <= maximumDistanceMeters
                else {
                    return nil
                }

                return (trail, nearest)
            }
            .min { $0.1 < $1.1 }?
            .0
    }
}
