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
    var maximumLeadMeters: Double = 0
    var maximumDeficitMeters: Double = 0
    var leadChangeCount: Int = 0

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
    case invalidTargetTime

    var errorDescription: String? {
        switch self {
        case .runningOnly:
            return "Ghost Race currently supports outdoor running workouts."
        case .missingRoute:
            return "This workout does not contain a GPS route, so it cannot be used as a ghost."
        case .routeTooShort:
            return "There is not enough GPS data in this workout to create a reliable ghost."
        case .invalidTargetTime:
            return "Choose a valid target finish time before starting the target ghost."
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
    private var maximumLeadMeters: Double = 0
    private var maximumDeficitMeters: Double = 0
    private var leadChangeCount = 0
    private var lastMeaningfulLeadSign = 0

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
        let timestampSpan =
            lastTimestamp.timeIntervalSince(
                firstTimestamp
            )

        let hasUsefulTimestamps =
            timestampSpan > 10

        let points = sampledIndices.map {
            index -> GhostRacePoint in

            let location = validRoute[index]
            let geometryProgress =
                totalGeometry > 0
                    ? cumulative[index] /
                        totalGeometry
                    : 0

            let rawElapsed: TimeInterval

            if hasUsefulTimestamps,
               duration > 0 {
                // Health route timestamps can span a noticeably different
                // wall-clock interval than HKWorkout.duration (GPS startup,
                // pauses and delayed route samples are common). Normalize the
                // route timeline to the authoritative workout duration while
                // preserving the original pacing shape. This prevents a Ghost
                // from reaching the finish kilometres too early.
                let timestampProgress =
                    min(
                        max(
                            location.timestamp
                                .timeIntervalSince(
                                    firstTimestamp
                                ) /
                            timestampSpan,
                            0
                        ),
                        1
                    )
                rawElapsed =
                    duration *
                    timestampProgress
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
        resetRaceDynamics()
    }

    func prepareTarget(
        route: TrainingRoute,
        targetDurationSeconds: TimeInterval
    ) throws {
        guard targetDurationSeconds >= 60 else {
            throw GhostRacePreparationError
                .invalidTargetTime
        }

        let routeCoordinates =
            route.coordinates
                .sorted {
                    $0.sequence < $1.sequence
                }

        guard routeCoordinates.count >= 2 else {
            throw GhostRacePreparationError
                .missingRoute
        }

        let locations =
            routeCoordinates.map {
                CLLocation(
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            }

        let cumulative =
            cumulativeDistances(
                for: locations
            )

        guard let totalDistance =
                cumulative.last,
              totalDistance >= 200
        else {
            throw GhostRacePreparationError
                .routeTooShort
        }

        let sampledIndices =
            downsampleIndices(
                count:
                    routeCoordinates.count,
                maximumPoints: 900
            )

        let points =
            sampledIndices.map {
                index -> GhostRacePoint in

                let coordinate =
                    routeCoordinates[index]
                let distance =
                    cumulative[index]
                let progress =
                    totalDistance > 0
                        ? distance /
                            totalDistance
                        : 0

                return GhostRacePoint(
                    id: index,
                    latitude:
                        coordinate.latitude,
                    longitude:
                        coordinate.longitude,
                    altitude:
                        coordinate.altitude,
                    elapsedTime:
                        targetDurationSeconds *
                        progress,
                    cumulativeMeters:
                        distance
                )
            }

        guard points.count >= 2 else {
            throw GhostRacePreparationError
                .routeTooShort
        }

        reference = GhostRaceReference(
            id: UUID(),
            sourceWorkoutID: route.id,
            title:
                "Target · \(route.title)",
            startedAt: Date(),
            durationSeconds:
                targetDurationSeconds,
            distanceMeters:
                totalDistance,
            points: points
        )

        comparison = nil
        result = nil
        errorMessage = nil
        lastMatchedIndex = nil
        resetRaceDynamics()
    }

    func prepare(
        reference: GhostRaceReference
    ) throws {
        guard reference.points.count >= 2,
              reference.routeDistanceMeters >= 200,
              reference.durationSeconds > 0
        else {
            throw GhostRacePreparationError
                .routeTooShort
        }

        self.reference = reference
        comparison = nil
        result = nil
        errorMessage = nil
        lastMatchedIndex = nil
        resetRaceDynamics()
    }

    func cancel() {
        reference = nil
        comparison = nil
        result = nil
        errorMessage = nil
        lastMatchedIndex = nil
        resetRaceDynamics()
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
                finishedAt: Date(),
                maximumLeadMeters:
                    maximumLeadMeters,
                maximumDeficitMeters:
                    maximumDeficitMeters,
                leadChangeCount:
                    leadChangeCount
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
                    expectedDistanceMeters:
                        snapshot.distanceMeters,
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

        let nextComparison =
            GhostRaceComparison(
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

        comparison = nextComparison
        recordRaceDynamics(
            signedDistanceMeters:
                nextComparison
                    .signedDistanceMeters
        )

        if snapshot.state == .completed {
            complete(
                snapshot: snapshot,
                reference: reference
            )
        }
    }

    func updatePhoneWorkout(
        location: CLLocation?,
        elapsedTime: TimeInterval,
        state: WatchWorkoutMirrorState
    ) {
        let snapshot =
            WatchWorkoutLiveSnapshot(
                kind: .running,
                state: state,
                startedAt: nil,
                capturedAt: Date(),
                elapsedTime:
                    max(elapsedTime, 0),
                heartRate: 0,
                activeCalories: 0,
                distanceMeters: 0,
                averageHeartRate: nil,
                maxHeartRate: nil,
                routePointCount:
                    location == nil ? 0 : 1,
                currentLatitude:
                    location?
                        .coordinate
                        .latitude,
                currentLongitude:
                    location?
                        .coordinate
                        .longitude
            )

        update(with: snapshot)
    }

    func temporaryRoute(
        ownerID: UUID,
        title: String? = nil,
        comparisonRouteID: UUID? = nil
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
            sharedSourceRouteID:
                comparisonRouteID
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
            finishedAt: Date(),
            maximumLeadMeters:
                maximumLeadMeters,
            maximumDeficitMeters:
                maximumDeficitMeters,
            leadChangeCount:
                leadChangeCount
        )
    }

    private func resetRaceDynamics() {
        maximumLeadMeters = 0
        maximumDeficitMeters = 0
        leadChangeCount = 0
        lastMeaningfulLeadSign = 0
    }

    private func recordRaceDynamics(
        signedDistanceMeters: Double
    ) {
        guard signedDistanceMeters.isFinite else {
            return
        }

        maximumLeadMeters =
            max(
                maximumLeadMeters,
                signedDistanceMeters
            )
        maximumDeficitMeters =
            max(
                maximumDeficitMeters,
                -signedDistanceMeters
            )

        let threshold = 8.0
        let sign: Int

        if signedDistanceMeters >= threshold {
            sign = 1
        } else if signedDistanceMeters <= -threshold {
            sign = -1
        } else {
            sign = 0
        }

        guard sign != 0 else {
            return
        }

        if lastMeaningfulLeadSign != 0,
           sign != lastMeaningfulLeadSign {
            leadChangeCount += 1
        }

        lastMeaningfulLeadSign = sign
    }

    private func nearestReferenceIndex(
        to location: CLLocation,
        expectedDistanceMeters: Double,
        in reference: GhostRaceReference
    ) -> Int? {
        guard !reference.points.isEmpty else {
            return nil
        }

        let routeDistance =
            max(
                reference.routeDistanceMeters,
                reference.points.last?
                    .cumulativeMeters ?? 0,
                1
            )
        let expectedDistance =
            min(
                max(
                    expectedDistanceMeters,
                    0
                ),
                routeDistance
            )
        let progressWindow =
            max(
                280,
                min(
                    routeDistance * 0.12,
                    900
                )
            )

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
                    range: lower...upper,
                    expectedDistanceMeters:
                        expectedDistance,
                    maximumProgressDriftMeters:
                        progressWindow
                ) {
                let localDistance =
                    location.distance(
                        from:
                            reference.points[
                                local
                            ].location
                    )

                if localDistance <= 220 {
                    return local
                }
            }
        }

        let expectedProgress =
            expectedDistance /
            routeDistance
        let expectedIndex =
            Int(
                (
                    expectedProgress *
                    Double(
                        reference.points.count - 1
                    )
                )
                .rounded()
            )
        let indexRadius =
            max(
                30,
                Int(
                    Double(reference.points.count) *
                    0.14
                )
            )
        let lower =
            max(
                expectedIndex - indexRadius,
                0
            )
        let upper =
            min(
                expectedIndex + indexRadius,
                reference.points.count - 1
            )

        guard let matched =
                nearestIndex(
                    to: location,
                    points: reference.points,
                    range: lower...upper,
                    expectedDistanceMeters:
                        expectedDistance,
                    maximumProgressDriftMeters:
                        progressWindow
                )
        else {
            return nil
        }

        let matchedDistance =
            location.distance(
                from:
                    reference.points[
                        matched
                    ].location
            )

        return matchedDistance <= 250
            ? matched
            : nil
    }

    private func nearestIndex(
        to location: CLLocation,
        points: [GhostRacePoint],
        range: ClosedRange<Int>,
        expectedDistanceMeters: Double? = nil,
        maximumProgressDriftMeters: Double? = nil
    ) -> Int? {
        var bestIndex: Int?
        var bestDistance =
            Double.greatestFiniteMagnitude

        for index in range {
            if let expectedDistanceMeters,
               let maximumProgressDriftMeters,
               abs(
                    points[index]
                        .cumulativeMeters -
                    expectedDistanceMeters
               ) >
                maximumProgressDriftMeters {
                continue
            }

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
