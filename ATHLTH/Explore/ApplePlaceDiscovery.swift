import CoreLocation
import Foundation
import MapKit

enum ApplePlaceKind: String, CaseIterable, Identifiable {
    case fitnessCenter
    case nature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fitnessCenter:
            return "Gym"
        case .nature:
            return "Nature"
        }
    }

    var systemImage: String {
        switch self {
        case .fitnessCenter:
            return "dumbbell.fill"
        case .nature:
            return "leaf.fill"
        }
    }
}

enum ApplePlaceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case gyms = "Gyms"
    case nature = "Nature"

    var id: String { rawValue }
}

struct AppleMapPlace: Identifiable {
    let id: String
    let applePlaceID: String?
    let name: String
    let kind: ApplePlaceKind
    let mapItem: MKMapItem

    var coordinate: CLLocationCoordinate2D {
        mapItem.placemark.coordinate
    }

    var phoneNumber: String? {
        mapItem.phoneNumber
    }

    var websiteURL: URL? {
        mapItem.url
    }

    var isPersistableForCheckIn: Bool {
        kind == .fitnessCenter &&
        applePlaceID != nil
    }

    func distance(
        from location: CLLocation?
    ) -> CLLocationDistance? {
        guard let location else {
            return nil
        }

        return location.distance(
            from: CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        )
    }
}

@MainActor
final class ApplePlaceDiscoveryService {
    func discover(
        region: MKCoordinateRegion
    ) async -> [AppleMapPlace] {
        async let gyms = pointOfInterestSearch(
            region: region,
            categories: [.fitnessCenter],
            kind: .fitnessCenter
        )

        async let naturePOIs = pointOfInterestSearch(
            region: region,
            categories: [
                .park,
                .nationalPark,
                .campground
            ],
            kind: .nature
        )

        async let trailFeatures = naturalFeatureSearch(
            region: region,
            query: "hiking trail"
        )

        let gymResults =
            await gyms
        let naturePOIResults =
            await naturePOIs
        let trailResults =
            await trailFeatures

        let insideRegion =
            (
                gymResults +
                naturePOIResults +
                trailResults
            )
            .filter {
                contains(
                    $0.coordinate,
                    in: region
                )
            }

        return deduplicated(
            insideRegion,
            center: region.center
        )
    }

    private func pointOfInterestSearch(
        region: MKCoordinateRegion,
        categories: [MKPointOfInterestCategory],
        kind: ApplePlaceKind
    ) async -> [AppleMapPlace] {
        let request = MKLocalPointsOfInterestRequest(
            coordinateRegion: region
        )
        request.pointOfInterestFilter =
            MKPointOfInterestFilter(
                including: categories
            )

        let search = MKLocalSearch(
            request: request
        )

        do {
            let response = try await search.start()
            return response.mapItems.compactMap {
                place(
                    from: $0,
                    kind: kind
                )
            }
        } catch is CancellationError {
            search.cancel()
            return []
        } catch {
            return []
        }
    }

    private func naturalFeatureSearch(
        region: MKCoordinateRegion,
        query: String
    ) async -> [AppleMapPlace] {
        let request = MKLocalSearch.Request()
        request.region = region
        request.naturalLanguageQuery = query
        request.resultTypes = [
            .pointOfInterest,
            .physicalFeature
        ]

        let search = MKLocalSearch(
            request: request
        )

        do {
            let response = try await search.start()

            return response.mapItems.compactMap {
                place(
                    from: $0,
                    kind: .nature
                )
            }
        } catch is CancellationError {
            search.cancel()
            return []
        } catch {
            return []
        }
    }

    private func place(
        from item: MKMapItem,
        kind: ApplePlaceKind
    ) -> AppleMapPlace? {
        let cleanName = item.name?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard let cleanName,
              !cleanName.isEmpty
        else {
            return nil
        }

        let coordinate =
            item.placemark.coordinate

        guard CLLocationCoordinate2DIsValid(
            coordinate
        ) else {
            return nil
        }

        let placeID =
            item.identifier?.rawValue

        let fallbackID =
            [
                kind.rawValue,
                cleanName.lowercased(),
                String(
                    format: "%.5f",
                    coordinate.latitude
                ),
                String(
                    format: "%.5f",
                    coordinate.longitude
                )
            ]
            .joined(separator: ":")

        return AppleMapPlace(
            id: placeID ?? fallbackID,
            applePlaceID: placeID,
            name: cleanName,
            kind: kind,
            mapItem: item
        )
    }

    private func contains(
        _ coordinate: CLLocationCoordinate2D,
        in region: MKCoordinateRegion
    ) -> Bool {
        let halfLatitude =
            region.span.latitudeDelta / 2
        let halfLongitude =
            region.span.longitudeDelta / 2

        return coordinate.latitude >=
            region.center.latitude - halfLatitude &&
            coordinate.latitude <=
            region.center.latitude + halfLatitude &&
            coordinate.longitude >=
            region.center.longitude - halfLongitude &&
            coordinate.longitude <=
            region.center.longitude + halfLongitude
    }

    private func deduplicated(
        _ places: [AppleMapPlace],
        center: CLLocationCoordinate2D
    ) -> [AppleMapPlace] {
        var bestByID:
            [String: AppleMapPlace] = [:]

        for place in places {
            if bestByID[place.id] == nil {
                bestByID[place.id] = place
            }
        }

        let centerLocation =
            CLLocation(
                latitude: center.latitude,
                longitude: center.longitude
            )

        let sorted = bestByID.values.sorted {
            let lhsDistance =
                CLLocation(
                    latitude:
                        $0.coordinate.latitude,
                    longitude:
                        $0.coordinate.longitude
                )
                .distance(
                    from: centerLocation
                )

            let rhsDistance =
                CLLocation(
                    latitude:
                        $1.coordinate.latitude,
                    longitude:
                        $1.coordinate.longitude
                )
                .distance(
                    from: centerLocation
                )

            return lhsDistance < rhsDistance
        }

        let gyms =
            sorted
                .filter {
                    $0.kind ==
                        .fitnessCenter
                }
                .prefix(12)

        let nature =
            sorted
                .filter {
                    $0.kind ==
                        .nature
                }
                .prefix(12)

        return Array(gyms) +
            Array(nature)
    }
}

@MainActor
final class ApplePlaceDiscoveryStore:
    ObservableObject {
    @Published private(set)
    var places: [AppleMapPlace] = []

    @Published private(set)
    var isLoading = false

    private let service:
        ApplePlaceDiscoveryService

    private var lastCenter:
        CLLocation?

    private var lastSpan:
        MKCoordinateSpan?

    private var lastRefreshAt:
        Date?

    private var requestID =
        UUID()

    init(
        service:
            ApplePlaceDiscoveryService =
                ApplePlaceDiscoveryService()
    ) {
        self.service = service
    }

    func refresh(
        region: MKCoordinateRegion,
        force: Bool = false
    ) async {
        let center =
            CLLocation(
                latitude:
                    region.center.latitude,
                longitude:
                    region.center.longitude
            )

        if !force,
           let lastCenter,
           let lastSpan,
           let lastRefreshAt,
           center.distance(
                from: lastCenter
           ) < 1_200,
           abs(
                region.span.latitudeDelta -
                lastSpan.latitudeDelta
           ) < 0.035,
           Date().timeIntervalSince(
                lastRefreshAt
           ) < 180,
           !places.isEmpty {
            return
        }

        let newRequestID =
            UUID()

        requestID =
            newRequestID

        isLoading = true

        let loaded =
            await service.discover(
                region: constrainedRegion(
                    region
                )
            )

        guard requestID ==
                newRequestID
        else {
            return
        }

        places =
            loaded

        lastCenter =
            center

        lastSpan =
            region.span

        lastRefreshAt =
            Date()

        isLoading =
            false
    }

    func filtered(
        by filter: ApplePlaceFilter
    ) -> [AppleMapPlace] {
        switch filter {
        case .all:
            return places

        case .gyms:
            return places.filter {
                $0.kind ==
                    .fitnessCenter
            }

        case .nature:
            return places.filter {
                $0.kind ==
                    .nature
            }
        }
    }

    private func constrainedRegion(
        _ region:
            MKCoordinateRegion
    ) -> MKCoordinateRegion {
        let maximumDelta =
            0.22

        return MKCoordinateRegion(
            center:
                region.center,
            span:
                MKCoordinateSpan(
                    latitudeDelta:
                        min(
                            max(
                                region.span
                                    .latitudeDelta,
                                0.02
                            ),
                            maximumDelta
                        ),
                    longitudeDelta:
                        min(
                            max(
                                region.span
                                    .longitudeDelta,
                                0.02
                            ),
                            maximumDelta
                        )
                )
        )
    }
}

struct AppleMapPlaceDetailView:
    View {
    @Environment(\.dismiss)
    private var dismiss

    let place: AppleMapPlace
    let userLocation: CLLocation?

    private let checkInRadiusMeters:
        CLLocationDistance = 150

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    mapCard
                    placeCard

                    if place.kind ==
                        .fitnessCenter {
                        checkInCard
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(
                ATHLTHPremiumCanvas()
            )
            .navigationTitle(
                place.name
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var mapCard:
        some View {
        Map(
            initialPosition:
                .region(
                    MKCoordinateRegion(
                        center:
                            place.coordinate,
                        latitudinalMeters:
                            1_600,
                        longitudinalMeters:
                            1_600
                    )
                )
        ) {
            Marker(
                place.name,
                systemImage:
                    place.kind
                        .systemImage,
                coordinate:
                    place.coordinate
            )
            .tint(
                place.kind ==
                    .fitnessCenter
                    ? ATHLTHTheme
                        .accentDeep
                    : ATHLTHTheme
                        .vitality
            )
        }
        .mapStyle(
            .standard(
                elevation:
                    .realistic
            )
        )
        .frame(height: 220)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
    }

    private var placeCard:
        some View {
        ATHLTHCard {
            HStack(
                alignment: .top,
                spacing: 14
            ) {
                Image(
                    systemName:
                        place.kind
                            .systemImage
                )
                .font(
                    .system(
                        size: 21,
                        weight:
                            .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
                .frame(
                    width: 48,
                    height: 48
                )
                .background(
                    ATHLTHTheme
                        .champagneSoft,
                    in:
                        RoundedRectangle(
                            cornerRadius:
                                15,
                            style:
                                .continuous
                        )
                )

                VStack(
                    alignment:
                        .leading,
                    spacing: 4
                ) {
                    Text(
                        place.kind
                            .title
                    )
                    .font(
                        .caption
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        .secondary
                    )

                    Text(
                        place.name
                    )
                    .font(
                        .title3
                            .weight(
                                .bold
                            )
                    )

                    if let distance =
                        place.distance(
                            from:
                                userLocation
                        ) {
                        Text(
                            distanceText(
                                distance
                            )
                        )
                        .font(
                            .caption
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }

                Spacer()
            }

            Button {
                place.mapItem
                    .openInMaps(
                        launchOptions:
                            nil
                    )
            } label: {
                Label(
                    "Open in Apple Maps",
                    systemImage:
                        "map.fill"
                )
                .font(
                    .subheadline
                        .weight(
                            .semibold
                        )
                )
                .frame(
                    maxWidth:
                        .infinity
                )
                .padding(
                    .vertical,
                    11
                )
            }
            .buttonStyle(
                .bordered
            )
            .padding(.top, 8)
        }
    }

    private var checkInCard:
        some View {
        ATHLTHCard {
            HStack(
                alignment: .top,
                spacing: 13
            ) {
                Image(
                    systemName:
                        isWithinCheckInRange
                            ? "checkmark.circle.fill"
                            : "location.circle.fill"
                )
                .font(.title2)
                .foregroundStyle(
                    isWithinCheckInRange
                        ? ATHLTHTheme
                            .vitality
                        : ATHLTHTheme
                            .premiumGold
                )

                VStack(
                    alignment:
                        .leading,
                    spacing: 5
                ) {
                    Text(
                        isWithinCheckInRange
                            ? "Within check-in range"
                            : "Workout check-in"
                    )
                    .font(
                        .headline
                    )

                    Text(
                        checkInMessage
                    )
                    .font(
                        .caption
                    )
                    .foregroundStyle(
                        .secondary
                    )
                    .fixedSize(
                        horizontal:
                            false,
                        vertical:
                            true
                    )
                }

                Spacer()
            }
        }
    }

    private var isWithinCheckInRange:
        Bool {
        guard let distance =
                place.distance(
                    from:
                        userLocation
                )
        else {
            return false
        }

        return distance <=
            checkInRadiusMeters
    }

    private var checkInMessage:
        String {
        guard place
                .isPersistableForCheckIn
        else {
            return "Apple Maps has not provided a persistent Place ID for this location, so ATHLTH will not use it for workout check-in."
        }

        if isWithinCheckInRange {
            return "ATHLTH can use this Apple Place ID for a strength-workout check-in. The actual workout link will be enabled in the workout flow."
        }

        return "For strength workouts, ATHLTH will offer check-in when you are within 150 m of this gym."
    }

    private func distanceText(
        _ distance:
            CLLocationDistance
    ) -> String {
        if distance < 1_000 {
            return "\(Int(distance.rounded())) m away"
        }

        return String(
            format:
                "%.1f km away",
            distance / 1_000
        )
    }
}
