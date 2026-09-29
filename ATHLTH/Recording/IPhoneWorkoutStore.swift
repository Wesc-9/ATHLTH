import AVFoundation
import CoreLocation
import Foundation
@preconcurrency import HealthKit
import UIKit

struct PhoneWorkoutPauseInterval: Codable, Equatable {
    let startedAt: Date
    var endedAt: Date?
}

struct PhoneRouteCompletionSummary: Codable, Hashable {
    var routeID: UUID
    var routeTitle: String
    var routeMatchPercent: Double
    var averageDeviationMeters: Double
    var maxDeviationMeters: Double
    var distanceMeters: Double
    var durationSeconds: TimeInterval
    var leaderboardEligible: Bool
    var personalBest: Bool
}

private enum IPhoneWorkoutHealthError: LocalizedError {
    case operationFailed(String)
    case workoutNotCreated

    var errorDescription: String? {
        switch self {
        case .operationFailed(let operation):
            return "Apple Health could not \(operation)."
        case .workoutNotCreated:
            return "Apple Health did not return the completed workout."
        }
    }
}

struct PhoneRoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let accuracy: Double
    let timestamp: Date
    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude; longitude = location.coordinate.longitude
        altitude = location.altitude; accuracy = location.horizontalAccuracy; timestamp = location.timestamp
    }
    var location: CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), altitude: altitude, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: timestamp)
    }
}

struct PhoneWorkout: Codable, Identifiable {
    var id = UUID()
    var walking: Bool
    var start: Date
    var end: Date?
    var accumulatedSeconds: TimeInterval = 0
    var resumedAt: Date?
    var lastCheckpoint: Date
    // Optional keeps workouts written by older TestFlight builds decodable.
    // New recordings use this to preserve pause/resume timing in HKWorkoutBuilder.
    var pauses: [PhoneWorkoutPauseInterval]? = nil
    var distanceMeters: Double = 0
    var points: [PhoneRoutePoint] = []
    var healthID: UUID?
    // Optional route metadata keeps older TestFlight recordings decodable
    // while allowing iPhone route runs to use the same selected route as Watch.
    var plannedRouteID: UUID? = nil
    var plannedRouteTitle: String? = nil
    var plannedRouteDistanceKilometers: Double? = nil
    var plannedRouteCoordinates: [RouteCoordinate]? = nil
    var plannedRouteSource: String? = nil
    var workoutTitle: String? = nil

    // Shared route-navigation state. All values are optional/defaulted so
    // workouts from older TestFlight builds continue to decode.
    var routeProgressPercent: Double? = nil
    var routeRemainingMeters: Double? = nil
    var routeDeviationMeters: Double? = nil
    var routeDistanceToStartMeters: Double? = nil
    var routeDistanceToFinishMeters: Double? = nil
    var routeNextBearingDegrees: Double? = nil
    var currentPaceSecondsPerKilometer: TimeInterval? = nil

    // The same structured running model is used by Apple Watch.
    var structuredRunningWorkout: WatchRunningWorkoutTransfer? = nil
    var structuredStepIndex: Int = 0
    var structuredStepStartElapsedTime: TimeInterval = 0
    var structuredStepStartDistanceMeters: Double = 0
    var structuredWorkoutComplete: Bool = false

    var audioCoachConfiguration:
        WatchAudioCoachConfiguration? = nil
    var routeAlertConfiguration:
        WatchRouteAlertConfiguration? = nil

    // Persist the final route analysis with the workout so completion details
    // survive relaunches without recomputing the full GPS trace.
    var finalRouteMatchPercent: Double? = nil
    var finalAverageDeviationMeters: Double? = nil
    var finalMaxDeviationMeters: Double? = nil
    var finalLeaderboardEligible: Bool? = nil
    var title: String {
        workoutTitle?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty == false
            ? workoutTitle!
            : walking
                ? "iPhone Walk"
                : "iPhone Run"
    }
    func elapsed(at date: Date) -> TimeInterval {
        accumulatedSeconds + (resumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
}

@MainActor
final class IPhoneWorkoutStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var active: PhoneWorkout?
    @Published private(set) var history: [PhoneWorkout] = []
    @Published var showingWorkout = false
    @Published private(set) var message: String?
    @Published private(set) var saving = false
    @Published private(set)
    var lastRouteCompletion: PhoneRouteCompletionSummary?
    private var accountID: UUID?
    private var pendingWalking: Bool?
    private var pendingRoute: TrainingRoute?
    private var pendingWorkoutTitle: String?
    private var pendingAudioCoach:
        WatchAudioCoachConfiguration?
    private var pendingStructuredWorkout:
        WatchRunningWorkoutTransfer?
    private var pendingRouteAlerts:
        WatchRouteAlertConfiguration?

    private var lastLocation: CLLocation?
    private var plannedRouteLocations: [CLLocation] = []
    private var plannedRouteCumulativeMeters: [Double] = []
    private var plannedRouteGeometryMeters: Double = 0

    private let speechSynthesizer =
        AVSpeechSynthesizer()
    private var nextDistanceAnnouncementMeters: Double?
    private var nextTimeAnnouncementSeconds: TimeInterval?
    private var offRouteStartedAt: Date?
    private var lastOffRouteAlertAt: Date?
    private var routeWasOff = false
    private var lastActiveCheckpointWriteAt: Date?
    private let activeCheckpointInterval: TimeInterval = 5
    private let manager = CLLocationManager()
    private let healthStore = HKHealthStore()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    func switchAccount(_ userID: UUID?) {
        guard accountID != userID else { return }
        pause()
        manager.stopUpdatingLocation()
        accountID = userID
        pendingWalking = nil
        pendingRoute = nil
        pendingWorkoutTitle = nil
        pendingAudioCoach = nil
        pendingStructuredWorkout = nil
        pendingRouteAlerts = nil
        resetRouteRuntime()
        lastRouteCompletion = nil
        active = userID.flatMap { AccountLocalStorage.read(PhoneWorkout.self, name: "phoneActive", userID: $0) }
        if var workout = active, workout.resumedAt != nil {
            workout.accumulatedSeconds = workout.elapsed(at: workout.lastCheckpoint)
            workout.resumedAt = nil

            if var pauses = workout.pauses,
               pauses.isEmpty || pauses.last?.endedAt != nil {
                pauses.append(
                    PhoneWorkoutPauseInterval(
                        startedAt: workout.lastCheckpoint,
                        endedAt: nil
                    )
                )
                workout.pauses = pauses
            }

            active = workout
        }
        history = userID.flatMap { AccountLocalStorage.read([PhoneWorkout].self, name: "phoneHistory", userID: $0) } ?? []
        if let active, history.contains(where: { $0.id == active.id }) { self.active = nil }
        showingWorkout = false
        message = active == nil ? nil : "Recovered workout paused at the last saved checkpoint. Resume when you are ready."
        lastActiveCheckpointWriteAt = nil
    }

    func start(
        walking: Bool,
        route: TrainingRoute? = nil,
        title: String? = nil,
        audioCoach:
            WatchAudioCoachConfiguration? = nil,
        structuredWorkout:
            WatchRunningWorkoutTransfer? = nil,
        routeAlerts:
            WatchRouteAlertConfiguration? = nil
    ) {
        guard accountID != nil, !saving else { return }
        showingWorkout = true
        guard active == nil else { return }

        pendingWalking = walking
        pendingRoute = route
        pendingWorkoutTitle = title
        pendingAudioCoach = audioCoach
        pendingStructuredWorkout = structuredWorkout
        pendingRouteAlerts = routeAlerts

        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            beginIfAuthorized()
        }
    }

    private func beginIfAuthorized() {
        guard let walking = pendingWalking else { return }
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            message = "Allow location access in iPhone Settings to record an outdoor workout."
            return
        }
        let route = pendingRoute
        let workoutTitle = pendingWorkoutTitle
        let audioCoach = pendingAudioCoach
        let structuredWorkout =
            pendingStructuredWorkout
        let routeAlerts =
            pendingRouteAlerts ?? .standard

        pendingWalking = nil
        pendingRoute = nil
        pendingWorkoutTitle = nil
        pendingAudioCoach = nil
        pendingStructuredWorkout = nil
        pendingRouteAlerts = nil

        cachePlannedRouteGeometry(route)
        resetCoachThresholds(
            configuration: audioCoach
        )
        resetRouteAlertRuntime()

        let now = Date()
        active = PhoneWorkout(
            walking: walking,
            start: now,
            resumedAt: now,
            lastCheckpoint: now,
            pauses: [],
            plannedRouteID: route?.id,
            plannedRouteTitle: route?.title,
            plannedRouteDistanceKilometers:
                route?.distanceKilometers,
            plannedRouteCoordinates:
                route?.coordinates,
            plannedRouteSource:
                route?.routeSource,
            workoutTitle: workoutTitle,
            structuredRunningWorkout:
                structuredWorkout,
            structuredStepIndex: 0,
            structuredStepStartElapsedTime: 0,
            structuredStepStartDistanceMeters: 0,
            structuredWorkoutComplete:
                structuredWorkout?.steps.isEmpty ?? true,
            audioCoachConfiguration:
                audioCoach,
            routeAlertConfiguration:
                routeAlerts
        )
        message = "Waiting for a reliable GPS signal. Keep your iPhone with you."
        lastLocation = nil
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        persistActiveCheckpoint(force: true)
        syncLiveActivity()
        announceStructuredStepIfNeeded(
            prefix: "Starting"
        )
    }

    func pause() {
        guard var workout = active, workout.resumedAt != nil else { return }
        let now = Date()
        workout.accumulatedSeconds = workout.elapsed(at: now)
        workout.resumedAt = nil
        workout.lastCheckpoint = now

        if var pauses = workout.pauses,
           pauses.isEmpty || pauses.last?.endedAt != nil {
            pauses.append(
                PhoneWorkoutPauseInterval(
                    startedAt: now,
                    endedAt: nil
                )
            )
            workout.pauses = pauses
        }

        active = workout
        manager.stopUpdatingLocation()
        lastLocation = nil
        persistActiveCheckpoint(force: true)
    }

    func resume() {
        guard var workout = active, workout.resumedAt == nil, !saving else { return }
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            message = "Allow location access in iPhone Settings before resuming."
            return
        }

        let now = Date()

        if var pauses = workout.pauses,
           let lastIndex = pauses.indices.last,
           pauses[lastIndex].endedAt == nil {
            pauses[lastIndex].endedAt = now
            workout.pauses = pauses
        }

        workout.resumedAt = now
        workout.lastCheckpoint = now
        active = workout
        lastLocation = nil
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        persistActiveCheckpoint(force: true)
    }

    func finish() async {
        guard !saving else { return }
        pause()
        guard var workout = active, let userID = accountID else { return }
        workout.end = Date()
        history.insert(workout, at: 0)
        active = nil
        persistActiveCheckpoint(force: true)
        persistHistory()
        await saveToHealth(workout, userID: userID)
    }

    func retryHealthSave(_ workout: PhoneWorkout) async {
        guard let accountID, !saving else { return }
        await saveToHealth(workout, userID: accountID)
    }

    private func saveToHealth(_ workout: PhoneWorkout, userID: UUID) async {
        saving = true
        defer { saving = false }

        guard HKHealthStore.isHealthDataAvailable(),
              let end = workout.end,
              healthStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized
        else {
            message = "Workout saved in ATHLTH. Enable Apple Health workout access to copy it to your history."
            return
        }

        do {
            // Idempotent retry: a successful Health save may precede an
            // interrupted local update. Reuse the already-created workout
            // instead of creating a duplicate.
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeyExternalUUID,
                allowedValues: [workout.id.uuidString]
            )
            let existing: HKWorkout? = try await withCheckedThrowingContinuation {
                continuation in
                healthStore.execute(
                    HKSampleQuery(
                        sampleType: .workoutType(),
                        predicate: predicate,
                        limit: 1,
                        sortDescriptors: nil
                    ) { _, samples, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(
                                returning: samples?.first as? HKWorkout
                            )
                        }
                    }
                )
            }

            guard accountID == userID else { return }

            let saved: HKWorkout
            let distanceWritten: Bool

            if let existing {
                saved = existing
                distanceWritten = true
            } else {
                let result = try await buildHealthWorkout(
                    workout,
                    end: end
                )
                saved = result.workout
                distanceWritten = result.distanceWritten

                // Route failure must not create a duplicate workout on retry.
                if !workout.points.isEmpty,
                   healthStore.authorizationStatus(
                        for: HKSeriesType.workoutRoute()
                   ) == .sharingAuthorized {
                    let route = HKWorkoutRouteBuilder(
                        healthStore: healthStore,
                        device: .local()
                    )

                    do {
                        try await route.insertRouteData(
                            workout.points.map(\.location)
                        )
                        _ = try await route.finishRoute(
                            with: saved,
                            metadata: nil
                        )
                    } catch {
                        message =
                            "Workout saved to Apple Health; the GPS route remains available in ATHLTH."
                    }
                }
            }

            guard accountID == userID else { return }

            if let index = history.firstIndex(
                where: { $0.id == workout.id }
            ) {
                history[index].healthID = saved.uuid
            }
            persistHistory()

            if message?.contains("GPS route remains") != true {
                if workout.distanceMeters > 0,
                   !distanceWritten {
                    message =
                        "Workout saved to ATHLTH and Apple Health. Allow ATHLTH to write walking/running distance in Health settings to include distance there."
                } else {
                    message =
                        "Workout saved to ATHLTH and Apple Health."
                }
            }

            await HealthKitManager.shared.refreshAll()
        } catch {
            if accountID == userID {
                message =
                    "Saved in ATHLTH. Apple Health copy failed: \(error.localizedDescription). You can retry below."
            }
        }
    }

    private func buildHealthWorkout(
        _ workout: PhoneWorkout,
        end: Date
    ) async throws -> (
        workout: HKWorkout,
        distanceWritten: Bool
    ) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType =
            workout.walking ? .walking : .running
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: .local()
        )

        do {
            try await beginCollection(
                builder,
                at: workout.start
            )

            try await addMetadata(
                [
                    HKMetadataKeyExternalUUID:
                        workout.id.uuidString,
                    HKMetadataKeySyncIdentifier:
                        "athlth-phone-" + workout.id.uuidString,
                    HKMetadataKeySyncVersion: 1,
                    HKMetadataKeyIndoorWorkout: false
                ],
                to: builder
            )

            let events = workoutEvents(
                for: workout,
                end: end
            )
            if !events.isEmpty {
                try await addWorkoutEvents(
                    events,
                    to: builder
                )
            }

            var distanceWritten = false

            if workout.distanceMeters > 0,
               let distanceType =
                    HKObjectType.quantityType(
                        forIdentifier:
                            .distanceWalkingRunning
                    ),
               healthStore.authorizationStatus(
                    for: distanceType
               ) == .sharingAuthorized {
                let distanceSample = HKQuantitySample(
                    type: distanceType,
                    quantity: HKQuantity(
                        unit: .meter(),
                        doubleValue:
                            workout.distanceMeters
                    ),
                    start: workout.start,
                    end: end
                )

                try await addSamples(
                    [distanceSample],
                    to: builder
                )
                distanceWritten = true
            }

            try await endCollection(
                builder,
                at: end
            )

            let saved =
                try await finishWorkout(builder)

            return (
                workout: saved,
                distanceWritten: distanceWritten
            )
        } catch {
            builder.discardWorkout()
            throw error
        }
    }

    private func workoutEvents(
        for workout: PhoneWorkout,
        end: Date
    ) -> [HKWorkoutEvent] {
        let pauseIntervals:
            [PhoneWorkoutPauseInterval]

        if let recorded = workout.pauses {
            pauseIntervals = recorded
        } else {
            // Compatibility for workouts recorded by older TestFlight
            // builds. Those builds stored active duration but not the actual
            // pause timestamps. Preserve the correct Health workout duration
            // by representing the missing inactive time as one synthetic
            // pause immediately before the end.
            let wallClockDuration =
                max(
                    0,
                    end.timeIntervalSince(
                        workout.start
                    )
                )
            let inactiveDuration =
                max(
                    0,
                    wallClockDuration -
                        workout.accumulatedSeconds
                )

            guard inactiveDuration > 0.5 else {
                return []
            }

            pauseIntervals = [
                PhoneWorkoutPauseInterval(
                    startedAt:
                        max(
                            workout.start,
                            end.addingTimeInterval(
                                -inactiveDuration
                            )
                        ),
                    endedAt: end
                )
            ]
        }

        return pauseIntervals.flatMap {
            interval -> [HKWorkoutEvent] in

            let pauseStart =
                min(
                    max(
                        interval.startedAt,
                        workout.start
                    ),
                    end
                )
            let resumeDate =
                min(
                    max(
                        interval.endedAt ?? end,
                        pauseStart
                    ),
                    end
                )

            guard resumeDate > pauseStart else {
                return []
            }

            return [
                HKWorkoutEvent(
                    type: .pause,
                    dateInterval: DateInterval(
                        start: pauseStart,
                        duration: 0
                    ),
                    metadata: nil
                ),
                HKWorkoutEvent(
                    type: .resume,
                    dateInterval: DateInterval(
                        start: resumeDate,
                        duration: 0
                    ),
                    metadata: nil
                )
            ]
        }
    }

    private func beginCollection(
        _ builder: HKWorkoutBuilder,
        at date: Date
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation:
                CheckedContinuation<Void, Error>) in
            builder.beginCollection(
                withStart: date
            ) { success, error in
                if let error {
                    continuation.resume(
                        throwing: error
                    )
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing:
                            IPhoneWorkoutHealthError
                                .operationFailed(
                                    "start the workout"
                                )
                    )
                }
            }
        }
    }

    private func addMetadata(
        _ metadata: [String: Any],
        to builder: HKWorkoutBuilder
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation:
                CheckedContinuation<Void, Error>) in
            builder.addMetadata(
                metadata
            ) { success, error in
                if let error {
                    continuation.resume(
                        throwing: error
                    )
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing:
                            IPhoneWorkoutHealthError
                                .operationFailed(
                                    "attach workout metadata"
                                )
                    )
                }
            }
        }
    }

    private func addWorkoutEvents(
        _ events: [HKWorkoutEvent],
        to builder: HKWorkoutBuilder
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation:
                CheckedContinuation<Void, Error>) in
            builder.addWorkoutEvents(
                events
            ) { success, error in
                if let error {
                    continuation.resume(
                        throwing: error
                    )
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing:
                            IPhoneWorkoutHealthError
                                .operationFailed(
                                    "save pause and resume events"
                                )
                    )
                }
            }
        }
    }

    private func addSamples(
        _ samples: [HKSample],
        to builder: HKWorkoutBuilder
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation:
                CheckedContinuation<Void, Error>) in
            builder.add(
                samples
            ) { success, error in
                if let error {
                    continuation.resume(
                        throwing: error
                    )
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing:
                            IPhoneWorkoutHealthError
                                .operationFailed(
                                    "attach workout samples"
                                )
                    )
                }
            }
        }
    }

    private func endCollection(
        _ builder: HKWorkoutBuilder,
        at date: Date
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation:
                CheckedContinuation<Void, Error>) in
            builder.endCollection(
                withEnd: date
            ) { success, error in
                if let error {
                    continuation.resume(
                        throwing: error
                    )
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing:
                            IPhoneWorkoutHealthError
                                .operationFailed(
                                    "end the workout"
                                )
                    )
                }
            }
        }
    }

    private func finishWorkout(
        _ builder: HKWorkoutBuilder
    ) async throws -> HKWorkout {
        try await withCheckedThrowingContinuation {
            (continuation:
                CheckedContinuation<HKWorkout, Error>) in
            builder.finishWorkout {
                workout,
                error in

                if let error {
                    continuation.resume(
                        throwing: error
                    )
                } else if let workout {
                    continuation.resume(
                        returning: workout
                    )
                } else {
                    continuation.resume(
                        throwing:
                            IPhoneWorkoutHealthError
                                .workoutNotCreated
                    )
                }
            }
        }
    }

    func checkpoint() {
        guard var workout = active else { return }
        workout.lastCheckpoint = Date()
        active = workout
        persistActiveCheckpoint(force: true)
    }

    private func persistActiveCheckpoint(
        force: Bool = false
    ) {
        guard let accountID,
              !UserDefaults.standard.bool(
                forKey: AccountLocalStorage.key(
                    "deleted",
                    userID: accountID
                )
              )
        else {
            return
        }

        let now = Date()

        if !force,
           let lastActiveCheckpointWriteAt,
           now.timeIntervalSince(lastActiveCheckpointWriteAt) <
                activeCheckpointInterval {
            return
        }

        if let active {
            AccountLocalStorage.write(
                active,
                name: "phoneActive",
                userID: accountID
            )
        } else {
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key(
                    "phoneActive",
                    userID: accountID
                )
            )
        }

        lastActiveCheckpointWriteAt = now
    }

    private func persistHistory() {
        guard let accountID,
              !UserDefaults.standard.bool(
                forKey: AccountLocalStorage.key(
                    "deleted",
                    userID: accountID
                )
              )
        else {
            return
        }

        AccountLocalStorage.write(
            history,
            name: "phoneHistory",
            userID: accountID
        )
        ATHLTHTrainingDataChangeSignal.post(userID: accountID)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.manager.authorizationStatus == .denied || self.manager.authorizationStatus == .restricted { self.pause() }
            self.beginIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.accept(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.message = "GPS is unavailable. Time continues; distance will resume when the signal returns."; self.lastLocation = nil }
    }

    private func accept(_ locations: [CLLocation]) {
        guard var workout = active, let resumedAt = workout.resumedAt else { return }
        for location in locations {
            guard location.timestamp >= resumedAt, abs(location.timestamp.timeIntervalSinceNow) < 15,
                  location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 30 else { continue }
            if let previous = lastLocation {
                let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
                guard seconds > 0 else { continue }
                let distance = location.distance(from: previous)
                // Ignore long signal gaps and implausible jumps rather than inventing distance.
                if seconds <= 30, distance / seconds <= 12 { workout.distanceMeters += distance }
            }
            lastLocation = location
            workout.points.append(PhoneRoutePoint(location))
            workout.lastCheckpoint = Date()
            message = nil
        }
        active = workout
        persistActiveCheckpoint()
    }
}
