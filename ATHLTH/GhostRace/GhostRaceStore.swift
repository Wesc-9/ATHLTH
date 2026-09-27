import Combine
import CoreLocation
import Foundation

struct GhostRacePoint: Identifiable, Hashable {
    let id: Int
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let elapsedTime: TimeInterval
    let cumulativeMeters: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }

    var location: CLLocation {
        CLLocation(
            latitude: latitude,
            longitude: longitude
        )
    }
}

struct GhostRaceReference: Identifiable, Hashable {
    let id: UUID
    let sourceWorkoutID: UUID
    let title: String
    let startedAt: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double
    let points: [GhostRacePoint]

    var routeDistanceMeters: Double {
        max(
            points.last?.cumulativeMeters ?? 0,
            distanceMeters
        )
    }
}

struct GhostRaceComparison: Equatable {
    let userLatitude: Double
    let userLongitude: Double
    let ghostLatitude: Double
    let ghostLongitude: Double
    let userProgress: Double
    let ghostProgress: Double
    let signedDistanceMeters: Double
    let signedTimeSeconds: TimeInterval
    let routeDeviationMeters: Double
    let updatedAt: Date

    var userCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: userLatitude,
            longitude: userLongitude
        )
    }

    var ghostCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: ghostLatitude,
            longitude: ghostLongitude
        )
    }

    var userIsAhead: Bool {
        signedDistanceMeters >= 0
    }
}

struct GhostRaceResult: Equatable {
    let sourceWorkoutID: UUID
    let completedRoute: Bool
    let elapsedTime: TimeInterval
    let referenceDuration: TimeInterval
    let signedTimeSeconds: TimeInterval?
    let finalDistanceDeltaMeters: Double?
    let finishedAt: Date

    var beatGhost: Bool? {
        guard completedRoute,
              let signedTimeSeconds
        else {
            return nil
        }

        return signedTimeSeconds > 0
    }
}

enum GhostRacePreparationError: LocalizedError {
    case runningOnly
    case missingRoute
    case routeTooShort

    var errorDescription: String? {
        switch self {
        case .runningOnly:
            return "Ghost Race currently supports outdoor running workouts."
        case .missingRoute:
            return "This workout does not contain a GPS route, so it cannot be used as a ghost."
        case .routeTooShort:
            return "There is not enough GPS data in this workout to create a reliable ghost."
        }
    }
}

@MainActor
final class GhostRaceStore: ObservableObject {
    @Published private(set) var reference: GhostRaceReference?
    @Published private(set) var comparison: GhostRaceComparison?
    @Published private(set) var result: GhostRaceResult?
    @Published var errorMessage: String?

    private var lastMatchedIndex: Int?

    var isPrepared: Bool {
        reference != nil
    }

    var isLive: Bool {
        reference != nil && result == nil
    }

    func prepare(
        workoutID: UUID,
        title: String,
        activity: WorkoutActivity,
        startedAt: Date,
        duration: TimeInterval,
        distanceMeters: Double?,
        route: [CLLocation]
    ) throws {
        guard activity == .running else {
            throw GhostRacePreparationError.runningOnly
        }

        let validRoute = route
            .filter {
                $0.coordinate.latitude.isFinite &&
                $0.coordinate.longitude.isFinite &&
                $0.horizontalAccuracy >= 0 &&
                $0.horizontalAccuracy <= 65
            }
            .sorted {
                $0.timestamp < $1.timestamp
            }

        guard validRoute.count >= 2 else {
            throw GhostRacePreparationError.missingRoute
        }

        let cumulative = cumulativeDistances(
            for: validRoute
        )

        guard let totalGeometry = cumulative.last,
              totalGeometry >= 250
        else {
            throw GhostRacePreparationError.routeTooShort
        }

        let sampledIndices = downsampleIndices(
            count: validRoute.count,
            maximumPoints: 900
        )

        let firstTimestamp =
            validRoute.first?.timestamp ?? startedAt
        let lastTimestamp =
            validRoute.last?.timestamp ?? startedAt

        let hasUsefulTimestamps =
            lastTimestamp.timeIntervalSince(
                firstTimestamp
            ) > 10

        let firstPointStartOffset =
            firstTimestamp.timeIntervalSince(
                startedAt
            )

        let timestampBaseline =
            hasUsefulTimestamps &&
            firstPointStartOffset >= -30 &&
            firstPointStartOffset <= 300
                ? startedAt
                : firstTimestamp

        let points = sampledIndices.map {
            index -> GhostRacePoint in

            let location = validRoute[index]
            let geometryProgress =
                totalGeometry > 0
                    ? cumulative[index] /
                        totalGeometry
                    : 0

            let rawElapsed: TimeInterval

            if hasUsefulTimestamps {
                rawElapsed =
                    location.timestamp
                        .timeIntervalSince(
                            timestampBaseline
                        )
            } else {
                rawElapsed =
                    max(duration, 0) *
                    geometryProgress
            }

            return GhostRacePoint(
                id: index,
                latitude:
                    location.coordinate.latitude,
                longitude:
                    location.coordinate.longitude,
                altitude:
                    location.altitude.isFinite
                        ? location.altitude
                        : nil,
                elapsedTime:
                    min(
                        max(rawElapsed, 0),
                        max(duration, rawElapsed)
                    ),
                cumulativeMeters:
                    cumulative[index]
            )
        }

        guard points.count >= 2 else {
            throw GhostRacePreparationError.routeTooShort
        }

        reference = GhostRaceReference(
            id: UUID(),
            sourceWorkoutID: workoutID,
            title: title,
            startedAt: startedAt,
            durationSeconds: max(duration, 0),
            distanceMeters:
                max(
                    distanceMeters ?? 0,
                    totalGeometry
                ),
            points: points
        )

        comparison = nil
        result = nil
        errorMessage = nil
        lastMatchedIndex = nil
    }

    func cancel() {
        reference = nil
        comparison = nil
        result = nil
        errorMessage = nil
        lastMatchedIndex = nil
    }

    func dismissResult() {
        cancel()
    }

    func update(
        with snapshot: WatchWorkoutLiveSnapshot?
    ) {
        guard let reference,
              let snapshot
        else {
            return
        }

        if snapshot.state == .failed {
            result = GhostRaceResult(
                sourceWorkoutID:
                    reference.sourceWorkoutID,
                completedRoute: false,
                elapsedTime:
                    snapshot.elapsedTime,
                referenceDuration:
                    reference.durationSeconds,
                signedTimeSeconds: nil,
                finalDistanceDeltaMeters:
                    comparison?
                        .signedDistanceMeters,
                finishedAt: Date()
            )
            return
        }

        guard let latitude =
                snapshot.currentLatitude,
              let longitude =
                snapshot.currentLongitude
        else {
            if snapshot.state == .completed {
                complete(
                    snapshot: snapshot,
                    reference: reference
                )
            }
            return
        }

        let currentLocation = CLLocation(
            latitude: latitude,
            longitude: longitude
        )

        guard let matchedIndex =
                nearestReferenceIndex(
                    to: currentLocation,
                    in: reference
                )
        else {
            return
        }

        lastMatchedIndex = matchedIndex

        let matched =
            reference.points[matchedIndex]
        let ghost =
            ghostPoint(
                at: snapshot.elapsedTime,
                in: reference
            )

        let routeDistance =
            max(
                reference.routeDistanceMeters,
                1
            )

        let userProgress =
            min(
                max(
                    matched.cumulativeMeters /
                    routeDistance,
                    0
                ),
                1
            )

        let ghostProgress =
            min(
                max(
                    ghost.cumulativeMeters /
                    routeDistance,
                    0
                ),
                1
            )

        let deviation =
            currentLocation.distance(
                from: matched.location
            )

        comparison = GhostRaceComparison(
            userLatitude: latitude,
            userLongitude: longitude,
            ghostLatitude:
                ghost.latitude,
            ghostLongitude:
                ghost.longitude,
            userProgress:
                userProgress,
            ghostProgress:
                ghostProgress,
            signedDistanceMeters:
                matched.cumulativeMeters -
                ghost.cumulativeMeters,
            signedTimeSeconds:
                matched.elapsedTime -
                snapshot.elapsedTime,
            routeDeviationMeters:
                deviation,
            updatedAt: Date()
        )

        if snapshot.state == .completed {
            complete(
                snapshot: snapshot,
                reference: reference
            )
        }
    }

    func temporaryRoute(
        ownerID: UUID,
        title: String? = nil
    ) -> TrainingRoute? {
        guard let reference,
              reference.points.count >= 2
        else {
            return nil
        }

        let coordinates =
            reference.points.enumerated().map {
                index,
                point in

                RouteCoordinate(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    altitude: point.altitude,
                    sequence: index
                )
            }

        return TrainingRoute(
            id: UUID(),
            ownerID: ownerID,
            title:
                title ??
                "Ghost · \(reference.title)",
            visibility: .privateOnly,
            coordinates: coordinates,
            distanceKilometers:
                reference.routeDistanceMeters /
                1_000,
            elevationGainMeters:
                elevationGain(
                    points: reference.points
                ),
            importedFilename: nil,
            createdAt: Date(),
            startName: "Ghost start",
            endName: "Ghost finish",
            expectedTravelTimeSeconds:
                reference.durationSeconds,
            routeSource: "ghost_race",
            sharedSourceOwnerID: nil,
            sharedSourceRouteID: nil
        )
    }

    private func complete(
        snapshot: WatchWorkoutLiveSnapshot,
        reference: GhostRaceReference
    ) {
        guard result == nil else {
            return
        }

        let progress =
            comparison?.userProgress ?? 0
        let completedRoute =
            progress >= 0.94

        let signedTime =
            completedRoute
                ? reference.durationSeconds -
                    snapshot.elapsedTime
                : nil

        result = GhostRaceResult(
            sourceWorkoutID:
                reference.sourceWorkoutID,
            completedRoute:
                completedRoute,
            elapsedTime:
                snapshot.elapsedTime,
            referenceDuration:
                reference.durationSeconds,
            signedTimeSeconds:
                signedTime,
            finalDistanceDeltaMeters:
                comparison?
                    .signedDistanceMeters,
            finishedAt: Date()
        )
    }

    private func nearestReferenceIndex(
        to location: CLLocation,
        in reference: GhostRaceReference
    ) -> Int? {
        guard !reference.points.isEmpty else {
            return nil
        }

        if let lastMatchedIndex {
            let lower =
                max(lastMatchedIndex - 30, 0)
            let upper =
                min(
                    lastMatchedIndex + 180,
                    reference.points.count - 1
                )

            if let local =
                nearestIndex(
                    to: location,
                    points: reference.points,
                    range: lower...upper
                ) {
                let localDistance =
                    location.distance(
                        from:
                            reference.points[
                                local
                            ].location
                    )

                if localDistance <= 180 {
                    return local
                }
            }
        }

        let initialUpper =
            min(
                max(
                    Int(
                        Double(reference.points.count) *
                        0.18
                    ),
                    24
                ),
                reference.points.count - 1
            )

        guard let initial =
                nearestIndex(
                    to: location,
                    points: reference.points,
                    range: 0...initialUpper
                )
        else {
            return nil
        }

        let initialDistance =
            location.distance(
                from:
                    reference.points[
                        initial
                    ].location
            )

        return initialDistance <= 250
            ? initial
            : nil
    }

    private func nearestIndex(
        to location: CLLocation,
        points: [GhostRacePoint],
        range: ClosedRange<Int>
    ) -> Int? {
        var bestIndex: Int?
        var bestDistance =
            Double.greatestFiniteMagnitude

        for index in range {
            let distance =
                location.distance(
                    from:
                        points[index].location
                )

            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    private func ghostPoint(
        at elapsedTime: TimeInterval,
        in reference: GhostRaceReference
    ) -> GhostRacePoint {
        let target =
            min(
                max(elapsedTime, 0),
                max(
                    reference.durationSeconds,
                    0
                )
            )

        var low = 0
        var high =
            reference.points.count - 1

        while low < high {
            let mid = (low + high + 1) / 2

            if reference.points[mid]
                .elapsedTime <= target {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return reference.points[low]
    }

    private func cumulativeDistances(
        for locations: [CLLocation]
    ) -> [Double] {
        guard !locations.isEmpty else {
            return []
        }

        var values =
            Array(
                repeating: 0.0,
                count: locations.count
            )

        guard locations.count > 1 else {
            return values
        }

        for index in 1..<locations.count {
            values[index] =
                values[index - 1] +
                locations[index].distance(
                    from:
                        locations[index - 1]
                )
        }

        return values
    }

    private func downsampleIndices(
        count: Int,
        maximumPoints: Int
    ) -> [Int] {
        guard count > maximumPoints,
              maximumPoints > 2
        else {
            return Array(0..<count)
        }

        let step =
            Double(count - 1) /
            Double(maximumPoints - 1)

        var result: [Int] = []
        result.reserveCapacity(maximumPoints)

        for sample in 0..<maximumPoints {
            let index =
                min(
                    Int(
                        (
                            Double(sample) *
                            step
                        ).rounded()
                    ),
                    count - 1
                )

            if result.last != index {
                result.append(index)
            }
        }

        if result.last != count - 1 {
            result.append(count - 1)
        }

        return result
    }

    private func elevationGain(
        points: [GhostRacePoint]
    ) -> Double? {
        let altitudes =
            points.compactMap(\.altitude)

        guard altitudes.count >= 2 else {
            return nil
        }

        var gain: Double = 0

        for index in 1..<altitudes.count {
            gain += max(
                altitudes[index] -
                altitudes[index - 1],
                0
            )
        }

        return gain
    }
}
