@preconcurrency import CoreLocation
import Foundation
@preconcurrency import MapKit
import Supabase

struct WorkoutPlaceCheckInRecord:
    Codable,
    Identifiable,
    Hashable {
    let id: UUID
    let userID: UUID
    let workoutID: UUID
    let applePlaceID: String
    let placeKind: String
    let checkedInAt: Date
    let distanceMeters: Double?
    let source: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case workoutID = "workout_id"
        case applePlaceID = "apple_place_id"
        case placeKind = "place_kind"
        case checkedInAt = "checked_in_at"
        case distanceMeters = "distance_meters"
        case source
        case createdAt = "created_at"
    }
}

private struct WorkoutPlaceCheckInWrite:
    Encodable {
    let userID: UUID
    let workoutID: UUID
    let applePlaceID: String
    let placeKind: String
    let checkedInAt: Date
    let distanceMeters: Double?
    let source: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case workoutID = "workout_id"
        case applePlaceID = "apple_place_id"
        case placeKind = "place_kind"
        case checkedInAt = "checked_in_at"
        case distanceMeters = "distance_meters"
        case source
    }
}

struct WorkoutPlacePresentation:
    Identifiable,
    Hashable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double?

    static func == (
        lhs: WorkoutPlacePresentation,
        rhs: WorkoutPlacePresentation
    ) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.coordinate.latitude ==
            rhs.coordinate.latitude &&
        lhs.coordinate.longitude ==
            rhs.coordinate.longitude &&
        lhs.distanceMeters ==
            rhs.distanceMeters
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(distanceMeters)
    }
}

@MainActor
final class SupabaseWorkoutPlaceCheckInService {
    private let client: SupabaseClient

    init(
        client: SupabaseClient =
            SupabaseEnvironment.client
    ) {
        self.client = client
    }

    func load(
        limit: Int = 250
    ) async throws ->
        [WorkoutPlaceCheckInRecord] {
        try await client
            .from("workout_place_checkins")
            .select()
            .order(
                "checked_in_at",
                ascending: false
            )
            .limit(
                min(
                    max(limit, 20),
                    500
                )
            )
            .execute()
            .value
    }

    func upsert(
        userID: UUID,
        workoutID: UUID,
        applePlaceID: String,
        distanceMeters: Double
    ) async throws {
        let payload =
            WorkoutPlaceCheckInWrite(
                userID: userID,
                workoutID: workoutID,
                applePlaceID: applePlaceID,
                placeKind: "fitness_center",
                checkedInAt: Date(),
                distanceMeters:
                    max(
                        0,
                        min(
                            distanceMeters,
                            150
                        )
                    ),
                source: "apple_maps"
            )

        try await client
            .from("workout_place_checkins")
            .upsert(
                payload,
                onConflict:
                    "user_id,workout_id"
            )
            .execute()
    }

    func remove(
        workoutID: UUID
    ) async throws {
        try await client
            .from("workout_place_checkins")
            .delete()
            .eq(
                "workout_id",
                value: workoutID
            )
            .execute()
    }
}

@MainActor
final class WorkoutPlaceCheckInStore:
    ObservableObject {
    @Published private(set)
    var records: [WorkoutPlaceCheckInRecord] = []

    @Published private(set)
    var resolvedPlaces:
        [String: WorkoutPlacePresentation] = [:]

    @Published private(set)
    var isLoading = false

    @Published var errorMessage: String?

    private let service:
        SupabaseWorkoutPlaceCheckInService

    private var lastRefreshAt: Date?

    // MapKit searches may take several seconds. A fresh result can be
    // reused when the picker reopens or GPS drifts a few meters.
    private var cachedNearbyOrigin: CLLocation?
    private var cachedNearbyAt: Date?
    private var cachedNearbyCandidates: [WorkoutPlacePresentation] = []

    init(
        service:
            SupabaseWorkoutPlaceCheckInService =
                SupabaseWorkoutPlaceCheckInService()
    ) {
        self.service = service
    }

    func refresh(
        force: Bool = false
    ) async {
        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(
                lastRefreshAt
           ) < 180,
           !records.isEmpty {
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
            let loaded =
                try await service.load()

            guard !Task.isCancelled else {
                return
            }

            records = loaded
            lastRefreshAt = Date()

            await resolveFrequentPlaces()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }

            errorMessage =
                error.localizedDescription
        }
    }

    func checkIn(
        workoutID: UUID,
        userID: UUID,
        place: WorkoutPlacePresentation
    ) async -> Bool {
        guard let distance =
                place.distanceMeters,
              distance.isFinite,
              distance >= 0,
              distance <= 150
        else {
            errorMessage =
                "You need to be within 150 m of the fitness center to check in."
            return false
        }

        do {
            try await service.upsert(
                userID: userID,
                workoutID: workoutID,
                applePlaceID: place.id,
                distanceMeters: distance
            )

            resolvedPlaces[place.id] =
                place

            await refresh(force: true)
            errorMessage = nil
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func remove(
        workoutID: UUID
    ) async -> Bool {
        do {
            try await service.remove(
                workoutID: workoutID
            )

            records.removeAll {
                $0.workoutID == workoutID
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func record(
        for workoutID: UUID
    ) -> WorkoutPlaceCheckInRecord? {
        records.first {
            $0.workoutID == workoutID
        }
    }

    func resolvedPlace(
        for workoutID: UUID
    ) -> WorkoutPlacePresentation? {
        guard let record =
                record(for: workoutID)
        else {
            return nil
        }

        return resolvedPlaces[
            record.applePlaceID
        ]
    }

    func resolvePlace(
        for workoutID: UUID
    ) async ->
        WorkoutPlacePresentation? {
        guard let record =
                record(for: workoutID)
        else {
            return nil
        }

        if let cached =
            resolvedPlaces[
                record.applePlaceID
            ] {
            return cached
        }

        let resolved =
            await Self.resolve(
                placeID:
                    record.applePlaceID
            )

        if let resolved {
            resolvedPlaces[
                record.applePlaceID
            ] = resolved
        }

        return resolved
    }

    func frequentPlaceIDs(
        limit: Int = 3
    ) -> [String] {
        let counts =
            Dictionary(
                grouping:
                    records,
                by: \.applePlaceID
            )
            .map {
                (
                    id: $0.key,
                    count: $0.value.count,
                    latest:
                        $0.value
                            .map(\.checkedInAt)
                            .max() ??
                        .distantPast
                )
            }
            .sorted {
                if $0.count == $1.count {
                    return $0.latest >
                        $1.latest
                }

                return $0.count >
                    $1.count
            }

        return counts
            .prefix(
                max(limit, 0)
            )
            .map(\.id)
    }

    func visitCount(
        placeID: String
    ) -> Int {
        records.reduce(into: 0) {
            result,
            record in

            if record.applePlaceID ==
                placeID {
                result += 1
            }
        }
    }

    func nearbyFitnessCenters(
        near location: CLLocation
    ) async throws ->
        [WorkoutPlacePresentation] {
        guard CLLocationCoordinate2DIsValid(
            location.coordinate
        ),
        location.coordinate.latitude.isFinite,
        location.coordinate.longitude.isFinite
        else {
            return []
        }

        if let cachedNearbyOrigin,
           let cachedNearbyAt,
           Date().timeIntervalSince(cachedNearbyAt) < 120,
           location.distance(from: cachedNearbyOrigin) < 35 {
            return nearbyWithinRange(
                cachedNearbyCandidates,
                from: location
            )
        }

        let request =
            MKLocalPointsOfInterestRequest(
                center:
                    location.coordinate,
                radius: 400
            )

        request.pointOfInterestFilter =
            MKPointOfInterestFilter(
                including: [
                    .fitnessCenter
                ]
            )

        let search =
            MKLocalSearch(
                request: request
            )

        let response =
            try await search.start()

        let places =
            response.mapItems
                .compactMap {
                    mapItem ->
                        WorkoutPlacePresentation?
                    in

                    guard let identifier =
                            mapItem.identifier,
                          let name =
                            mapItem.name?
                                .trimmingCharacters(
                                    in:
                                        .whitespacesAndNewlines
                                ),
                          !name.isEmpty
                    else {
                        return nil
                    }

                    let coordinate =
                        mapItem.placemark.coordinate
                    let mapLocation =
                        CLLocation(
                            latitude:
                                coordinate.latitude,
                            longitude:
                                coordinate.longitude
                        )
                    let distance =
                        location.distance(
                            from:
                                mapLocation
                        )

                    guard distance.isFinite,
                          distance <= 400
                    else {
                        return nil
                    }

                    return
                        WorkoutPlacePresentation(
                            id:
                                identifier.rawValue,
                            name: name,
                            coordinate:
                                coordinate,
                            distanceMeters:
                                distance
                        )
                }
                .sorted {
                    (
                        $0.distanceMeters ??
                        .greatestFiniteMagnitude
                    ) <
                    (
                        $1.distanceMeters ??
                        .greatestFiniteMagnitude
                    )
                }

        cachedNearbyOrigin = location
        cachedNearbyAt = Date()
        cachedNearbyCandidates = places

        let visible = nearbyWithinRange(
            places,
            from: location
        )
        for place in visible {
            resolvedPlaces[place.id] = place
        }

        return visible
    }

    private func nearbyWithinRange(
        _ candidates: [WorkoutPlacePresentation],
        from location: CLLocation
    ) -> [WorkoutPlacePresentation] {
        candidates.compactMap { place in
            let distance = location.distance(
                from: CLLocation(
                    latitude: place.coordinate.latitude,
                    longitude: place.coordinate.longitude
                )
            )
            guard distance.isFinite,
                  distance >= 0,
                  distance <= 150 else {
                return nil
            }

            return WorkoutPlacePresentation(
                id: place.id,
                name: place.name,
                coordinate: place.coordinate,
                distanceMeters: distance
            )
        }
        .sorted {
            ($0.distanceMeters ?? .greatestFiniteMagnitude) <
            ($1.distanceMeters ?? .greatestFiniteMagnitude)
        }
    }

    func resolvedFrequentPlaces(
        near location: CLLocation?
    ) async ->
        [WorkoutPlacePresentation] {
        var result:
            [WorkoutPlacePresentation] = []

        for placeID in
            frequentPlaceIDs(limit: 4) {
            var place:
                WorkoutPlacePresentation?

            if let cached =
                resolvedPlaces[
                    placeID
                ] {
                place = cached
            } else {
                place =
                    await Self.resolve(
                        placeID: placeID
                    )
            }

            if let location,
               let existing = place {
                let distance =
                    location.distance(
                        from:
                            CLLocation(
                                latitude:
                                    existing
                                        .coordinate
                                        .latitude,
                                longitude:
                                    existing
                                        .coordinate
                                        .longitude
                            )
                    )

                place =
                    WorkoutPlacePresentation(
                        id: existing.id,
                        name: existing.name,
                        coordinate:
                            existing.coordinate,
                        distanceMeters:
                            distance
                    )
            }

            if let place {
                resolvedPlaces[
                    placeID
                ] = place
                result.append(place)
            }
        }

        return result
    }

    private func resolveFrequentPlaces()
        async {
        for placeID in
            frequentPlaceIDs(limit: 6) {
            guard resolvedPlaces[
                    placeID
                  ] == nil
            else {
                continue
            }

            guard let place =
                    await Self.resolve(
                        placeID: placeID
                    )
            else {
                continue
            }

            resolvedPlaces[
                placeID
            ] = place
        }
    }

    private static func resolve(
        placeID: String
    ) async ->
        WorkoutPlacePresentation? {
        guard let identifier =
                MKMapItem.Identifier(
                    rawValue: placeID
                )
        else {
            return nil
        }

        let request =
            MKMapItemRequest(
                mapItemIdentifier:
                    identifier
            )

        do {
            let mapItem =
                try await request.mapItem

            guard let name =
                    mapItem.name?
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        ),
                  !name.isEmpty
            else {
                return nil
            }

            return
                WorkoutPlacePresentation(
                    id: placeID,
                    name: name,
                    coordinate:
                        mapItem
                            .placemark
                            .coordinate,
                    distanceMeters: nil
                )
        } catch {
            return nil
        }
    }
}
