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
            routeSource: source
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

/// Prevent duplicate public markers when overlapping Explore cells return
/// the same physical trail with different Kartverket / OSM source IDs.
/// This supplements server-side deduplication during cache warming.
enum PublicTrailDeduplicator {
    static func unique(_ trails: [PublicTrailRecord]) -> [PublicTrailRecord] {
        let prioritized = trails.sorted {
            let lhs = priority($0), rhs = priority($1)
            if lhs != rhs { return lhs > rhs }
            return $0.id.uuidString < $1.id.uuidString
        }
        var seen = Set<UUID>()
        var selected: [PublicTrailRecord] = []
        for trail in prioritized {
            guard seen.insert(trail.id).inserted else { continue }
            if selected.contains(where: {
                $0.source != trail.source && sameGeometry($0, trail)
            }) { continue }
            selected.append(trail)
        }
        return selected
    }

    private static func priority(_ trail: PublicTrailRecord) -> Int {
        (trail.athlthVerified ? 4 : 0) +
        (trail.source == "kartverket_turrutebasen" ? 2 : 1)
    }

    private static func meters(_ a: RouteCoordinate, _ b: RouteCoordinate) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private static func sameGeometry(_ lhs: PublicTrailRecord, _ rhs: PublicTrailRecord) -> Bool {
        let length = min(lhs.distanceKilometers, rhs.distanceKilometers)
        guard length >= 0.5,
              abs(lhs.distanceKilometers - rhs.distanceKilometers) <= max(0.18, length * 0.10),
              lhs.coordinates.count >= 2, rhs.coordinates.count >= 2
        else { return false }

        let centerDistance = CLLocation(
            latitude: lhs.centerLatitude, longitude: lhs.centerLongitude
        ).distance(from: CLLocation(
            latitude: rhs.centerLatitude, longitude: rhs.centerLongitude
        ))
        if centerDistance > max(700, length * 120) {
            let a = lhs.coordinates, b = rhs.coordinates
            guard let aFirst = a.first, let aLast = a.last,
                  let bFirst = b.first, let bLast = b.last else { return false }
            let forward = max(meters(aFirst, bFirst), meters(aLast, bLast))
            let reversed = max(meters(aFirst, bLast), meters(aLast, bFirst))
            if min(forward, reversed) > 350 { return false }
        }

        let nameMatches = lhs.name.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                          locale: .current)
            == rhs.name.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                locale: .current)
        let required = nameMatches ? 0.74 : 0.84
        return overlap(lhs.coordinates, rhs.coordinates) >= required &&
            overlap(rhs.coordinates, lhs.coordinates) >= required
    }

    private static func overlap(
        _ sample: [RouteCoordinate], _ target: [RouteCoordinate]
    ) -> Double {
        let count = min(16, sample.count)
        guard count > 1, target.count > 1 else { return 0 }
        var matching = 0
        for index in 0..<count {
            let pointIndex = Int(
                (Double(index) * Double(sample.count - 1) / Double(count - 1)).rounded()
            )
            if metersToPath(sample[pointIndex], target) <= 90 { matching += 1 }
        }
        return Double(matching) / Double(count)
    }

    private static func metersToPath(
        _ point: RouteCoordinate, _ line: [RouteCoordinate]
    ) -> Double {
        let latitudeMeters = 111_195.0
        let longitudeMeters = latitudeMeters * cos(point.latitude * .pi / 180)
        var nearest = Double.infinity
        for index in 1..<line.count {
            let first = line[index - 1], last = line[index]
            let x = (first.longitude - point.longitude) * longitudeMeters
            let y = (first.latitude - point.latitude) * latitudeMeters
            let dx = (last.longitude - first.longitude) * longitudeMeters
            let dy = (last.latitude - first.latitude) * latitudeMeters
            let squared = dx * dx + dy * dy
            let fraction = squared > 0 ? max(0, min(1, -(x * dx + y * dy) / squared)) : 0
            nearest = min(nearest, hypot(x + fraction * dx, y + fraction * dy))
            if nearest < 8 { break }
        }
        return nearest
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
        guard CLLocationCoordinate2DIsValid(region.center),
              region.span.latitudeDelta.isFinite,
              region.span.longitudeDelta.isFinite,
              region.span.latitudeDelta > 0,
              region.span.longitudeDelta > 0 else { return }

        let center = CLLocation(latitude: region.center.latitude,
                                longitude: region.center.longitude)
        let corner = CLLocation(
            latitude: min(89.9, region.center.latitude + region.span.latitudeDelta / 2),
            longitude: min(179.9, region.center.longitude + region.span.longitudeDelta / 2)
        )
        let radius = center.distance(from: corner) / 1000
        if radius <= 19 {
            await refresh(near: center, radiusKilometers: max(3, radius + 1), force: force)
            return
        }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let tileRadius = min(20.0, max(12.0, radius / 2 + 2))
        let lat = region.span.latitudeDelta / 4
        let lon = region.span.longitudeDelta / 4
        let centers = [
            CLLocation(latitude: region.center.latitude - lat, longitude: region.center.longitude - lon),
            CLLocation(latitude: region.center.latitude - lat, longitude: region.center.longitude + lon),
            CLLocation(latitude: region.center.latitude + lat, longitude: region.center.longitude - lon),
            CLLocation(latitude: region.center.latitude + lat, longitude: region.center.longitude + lon)
        ].filter { CLLocationCoordinate2DIsValid($0.coordinate) }
        let service = self.service
        let responses = await withTaskGroup(
            of: PublicTrailDiscoveryResponse?.self,
            returning: [PublicTrailDiscoveryResponse].self
        ) { group in
            for place in centers {
                group.addTask {
                    try? await service.discover(
                        near: place, radiusKilometers: tileRadius, forceRefresh: force
                    )
                }
            }
            var values: [PublicTrailDiscoveryResponse] = []
            for await item in group {
                if let item { values.append(item) }
            }
            return values
        }
        guard !Task.isCancelled else { return }
        guard !responses.isEmpty else {
            if trails.isEmpty {
                errorMessage = ATHLTHLocalization.choose(
                    english: "Unable to load trails in this area. Try again.",
                    norwegian: "Kunne ikke hente turstier i området. Prøv igjen."
                )
            }
            return
        }
        var found: [UUID: PublicTrailRecord] = [:]
        for result in responses {
            for trail in result.trails where trail.isUsable {
                found[trail.id] = trail
            }
        }
        trails = PublicTrailDeduplicator.unique(Array(found.values))
        attribution = responses.contains { $0.attribution.contains("Kartverket") }
            ? "© OpenStreetMap contributors · © Kartverket"
            : "© OpenStreetMap contributors"
        lastRefreshAt = Date()
        lastCenter = center
        isWarmingCache = trails.isEmpty && responses.contains(where: { $0.isRefreshing })
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

        trails = PublicTrailDeduplicator.unique(usable)

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
