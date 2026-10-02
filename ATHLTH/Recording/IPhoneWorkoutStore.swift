import AVFoundation
import CoreLocation
import Foundation
@preconcurrency import HealthKit
import UIKit

@MainActor
enum ATHLTHWorkoutScreenAwake {
    private static var reasons: Set<String> = []

    static func set(
        _ enabled: Bool,
        reason: String
    ) {
        if enabled {
            reasons.insert(reason)
        } else {
            reasons.remove(reason)
        }

        let shouldStayAwake =
            !reasons.isEmpty

        if UIApplication.shared
            .isIdleTimerDisabled !=
            shouldStayAwake {
            UIApplication.shared
                .isIdleTimerDisabled =
                shouldStayAwake
        }
    }
}

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
    var leaderboardRank: Int? = nil
    var leaderboardFieldSize: Int? = nil
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
    var autoPauseEnabled: Bool? = nil
    var distanceMeters: Double = 0
    var points: [PhoneRoutePoint] = []
    var healthID: UUID?
    // Optional route metadata keeps older TestFlight recordings decodable
    // while allowing iPhone route runs to use the same selected route as Watch.
    var plannedRouteID: UUID? = nil
    var plannedComparisonRouteID: UUID? = nil
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
    var structuredStepIndex: Int? = nil
    var structuredStepStartElapsedTime: TimeInterval? = nil
    var structuredStepStartDistanceMeters: Double? = nil
    var structuredWorkoutComplete: Bool? = nil

    var audioCoachConfiguration:
        WatchAudioCoachConfiguration? = nil
    var routeAlertConfiguration:
        WatchRouteAlertConfiguration? = nil
    var ghostAudioConfiguration:
        WatchGhostRaceAudioConfiguration? = nil
    var ghostRaceTitle: String? = nil
    var ghostDistanceDeltaMeters: Double? = nil
    var ghostTimeDeltaSeconds: TimeInterval? = nil

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
final class IPhoneWorkoutStore:
    NSObject,
    ObservableObject,
    CLLocationManagerDelegate,
    AVSpeechSynthesizerDelegate
{
    @Published private(set) var active: PhoneWorkout?
    @Published private(set) var history: [PhoneWorkout] = []
    @Published var showingWorkout = false
    @Published private(set) var message: String?
    @Published private(set) var saving = false
    @Published private(set) var automaticPauseActive = false
    @Published private(set) var completionStartedWorkout: PhoneWorkout?
    @Published private(set) var lastCompletedWorkout: PhoneWorkout?
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
    private var pendingGhostAudio:
        WatchGhostRaceAudioConfiguration?
    private var pendingAutoPauseEnabled: Bool = false

    private var lastLocation: CLLocation?
    private var autoPauseDetector =
        OutdoorAutoPauseDetector()
    private var plannedRouteLocations: [CLLocation] = []
    private var plannedRouteCumulativeMeters: [Double] = []
    private var plannedRouteGeometryMeters: Double = 0

    private let speechSynthesizer =
        AVSpeechSynthesizer()
    private var guidancePriorityGate =
        ATHLTHGuidancePriorityGate()
    private var nextDistanceAnnouncementMeters: Double?
    private var nextTimeAnnouncementSeconds: TimeInterval?
    private var offRouteStartedAt: Date?
    private var lastOffRouteAlertAt: Date?
    private var routeWasOff = false
    private var nextGhostDistanceAnnouncementMeters: Double?
    private var nextGhostTimeAnnouncementSeconds: TimeInterval?
    private var lastGhostAnnouncedLeadMeters: Double?
    private var lastGhostLeadAlertAt: Date?
    private var lastGhostLeadSign = 0
    private var lastActiveCheckpointWriteAt: Date?
    private let activeCheckpointInterval: TimeInterval = 5
    private let manager = CLLocationManager()
    private let healthStore = HKHealthStore()

    override init() {
        super.init()
        manager.delegate = self
        speechSynthesizer.delegate = self
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
        pendingGhostAudio = nil
        pendingAutoPauseEnabled = false
        automaticPauseActive = false
        autoPauseDetector.reset(enabled: false)
        resetRouteRuntime()
        lastRouteCompletion = nil
        completionStartedWorkout = nil
        lastCompletedWorkout = nil
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

        if let active {
            restoreRouteGeometry(
                from: active
            )
            resetCoachThresholds(
                configuration:
                    active
                        .audioCoachConfiguration
            )
            resetRouteAlertRuntime()
            resetGhostRuntime(
                configuration:
                    active
                        .ghostAudioConfiguration
            )
            guidancePriorityGate.reset()
        }

        lastRouteCompletion =
            history.first.flatMap {
                workout in

                guard let routeID =
                        workout.plannedRouteID,
                      let routeTitle =
                        workout.plannedRouteTitle,
                      let match =
                        workout
                            .finalRouteMatchPercent,
                      let average =
                        workout
                            .finalAverageDeviationMeters,
                      let maximum =
                        workout
                            .finalMaxDeviationMeters
                else {
                    return nil
                }

                return PhoneRouteCompletionSummary(
                    routeID: routeID,
                    routeTitle: routeTitle,
                    routeMatchPercent: match,
                    averageDeviationMeters:
                        average,
                    maxDeviationMeters:
                        maximum,
                    distanceMeters:
                        workout.distanceMeters,
                    durationSeconds:
                        workout
                            .accumulatedSeconds,
                    leaderboardEligible:
                        workout
                            .finalLeaderboardEligible ??
                        false,
                    personalBest: false
                )
            }

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
            WatchRouteAlertConfiguration? = nil,
        ghostUpdates:
            WatchGhostRaceAudioConfiguration? = nil,
        autoPauseEnabled: Bool = false
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
        pendingGhostAudio = ghostUpdates
        pendingAutoPauseEnabled =
            autoPauseEnabled

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
        let ghostUpdates =
            pendingGhostAudio
        let autoPauseEnabled =
            pendingAutoPauseEnabled

        pendingWalking = nil
        pendingRoute = nil
        pendingWorkoutTitle = nil
        pendingAudioCoach = nil
        pendingStructuredWorkout = nil
        pendingRouteAlerts = nil
        pendingGhostAudio = nil
        pendingAutoPauseEnabled = false

        cachePlannedRouteGeometry(route)
        resetCoachThresholds(
            configuration: audioCoach
        )
        resetRouteAlertRuntime()
        resetGhostRuntime(
            configuration:
                ghostUpdates
        )
        guidancePriorityGate.reset()

        let now = Date()
        active = PhoneWorkout(
            walking: walking,
            start: now,
            resumedAt: now,
            lastCheckpoint: now,
            pauses: [],
            autoPauseEnabled:
                autoPauseEnabled,
            plannedRouteID: route?.id,
            plannedComparisonRouteID:
                route?.sharedSourceRouteID ??
                route?.id,
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
                routeAlerts,
            ghostAudioConfiguration:
                ghostUpdates
        )
        message = "Waiting for a reliable GPS signal. Keep your iPhone with you."
        lastLocation = nil
        automaticPauseActive = false
        autoPauseDetector.reset(
            enabled: autoPauseEnabled
        )
        manager.distanceFilter =
            autoPauseEnabled ? 1 : 5
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        persistActiveCheckpoint(force: true)
        syncLiveActivity()

        if audioCoach?.enabled == true,
           audioCoach?.shouldAnnounceWorkoutStart == true {
            speak(
                localizedCoachPhrase(
                    english: "Audio Coach ready. Workout started.",
                    norwegian: "Audio Coach er klar. Økten er startet.",
                    configuration: audioCoach
                ),
                configuration: audioCoach,
                priority: .routineCoach
            )
        }

        announceStructuredStepIfNeeded(
            prefix: "Starting"
        )
    }

    func pause() {
        guard var workout = active else {
            return
        }

        let now = Date()

        if automaticPauseActive {
            // Turning an automatic pause into a manual pause must prevent the
            // motion detector from resuming the workout behind the user's back.
            automaticPauseActive = false
            autoPauseDetector.reset(
                enabled: false
            )
            active = workout
            manager.stopUpdatingLocation()
            lastLocation = nil
            message = ATHLTHLocalization.choose(
                english: "Workout paused.",
                norwegian: "Økten er satt på pause."
            )
            persistActiveCheckpoint(
                force: true
            )
            syncLiveActivity()
            return
        }

        guard workout.resumedAt != nil else {
            return
        }

        workout.accumulatedSeconds =
            workout.elapsed(at: now)
        workout.resumedAt = nil
        workout.lastCheckpoint = now

        if var pauses = workout.pauses,
           pauses.isEmpty ||
            pauses.last?.endedAt != nil {
            pauses.append(
                PhoneWorkoutPauseInterval(
                    startedAt: now,
                    endedAt: nil
                )
            )
            workout.pauses = pauses
        }

        active = workout
        autoPauseDetector.reset(
            enabled: false
        )
        manager.stopUpdatingLocation()
        lastLocation = nil
        persistActiveCheckpoint(force: true)
        syncLiveActivity()

        if workout
            .audioCoachConfiguration?
            .enabled == true,
           workout
            .audioCoachConfiguration?
            .shouldAnnouncePauseResume == true {
            speak(
                localizedCoachPhrase(
                    english: "Workout paused.",
                    norwegian: "Økten er satt på pause.",
                    configuration:
                        workout
                            .audioCoachConfiguration
                ),
                configuration:
                    workout
                        .audioCoachConfiguration,
                priority:
                    .structuredStep
            )
        }
    }

    func resume() {
        guard var workout = active,
              workout.resumedAt == nil,
              !saving
        else {
            return
        }

        guard
            manager.authorizationStatus ==
                .authorizedAlways ||
            manager.authorizationStatus ==
                .authorizedWhenInUse
        else {
            message =
                "Allow location access in iPhone Settings before resuming."
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
        automaticPauseActive = false
        autoPauseDetector.reset(
            enabled:
                workout.autoPauseEnabled ??
                false
        )
        manager.distanceFilter =
            (workout.autoPauseEnabled ?? false)
                ? 1
                : 5
        lastLocation = nil
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        message = nil
        persistActiveCheckpoint(force: true)
        syncLiveActivity()

        if workout
            .audioCoachConfiguration?
            .enabled == true,
           workout
            .audioCoachConfiguration?
            .shouldAnnouncePauseResume == true {
            speak(
                localizedCoachPhrase(
                    english: "Workout resumed.",
                    norwegian: "Økten fortsetter.",
                    configuration:
                        workout
                            .audioCoachConfiguration
                ),
                configuration:
                    workout
                        .audioCoachConfiguration,
                priority:
                    .structuredStep
            )
        }
    }

    private func applyAutomaticPause(
        workout: inout PhoneWorkout,
        at date: Date
    ) {
        guard workout.resumedAt != nil else {
            return
        }

        workout.accumulatedSeconds =
            workout.elapsed(at: date)
        workout.resumedAt = nil
        workout.lastCheckpoint = date

        if var pauses = workout.pauses,
           pauses.isEmpty ||
            pauses.last?.endedAt != nil {
            pauses.append(
                PhoneWorkoutPauseInterval(
                    startedAt: date,
                    endedAt: nil
                )
            )
            workout.pauses = pauses
        }

        automaticPauseActive = true
        lastLocation = nil
        message = ATHLTHLocalization.choose(
            english: "Auto-pause · waiting for movement",
            norwegian: "Auto-pause · venter på bevegelse"
        )
    }

    private func applyAutomaticResume(
        workout: inout PhoneWorkout,
        at date: Date
    ) {
        guard automaticPauseActive else {
            return
        }

        if var pauses = workout.pauses,
           let lastIndex = pauses.indices.last,
           pauses[lastIndex].endedAt == nil {
            pauses[lastIndex].endedAt = date
            workout.pauses = pauses
        }

        workout.resumedAt = date
        workout.lastCheckpoint = date
        automaticPauseActive = false
        lastLocation = nil
        message = nil
    }

    func finish() async {
        guard !saving else { return }
        pause()

        guard var workout = active,
              let userID = accountID
        else {
            return
        }

        workout.end = Date()
        let completion =
            routeCompletionSummary(
                for: workout
            )

        if let completion {
            workout.finalRouteMatchPercent =
                completion.routeMatchPercent
            workout.finalAverageDeviationMeters =
                completion.averageDeviationMeters
            workout.finalMaxDeviationMeters =
                completion.maxDeviationMeters
            workout.finalLeaderboardEligible =
                completion.leaderboardEligible
            lastRouteCompletion = completion
        }

        syncLiveActivity(
            workout: workout,
            state: .completed
        )

        history.insert(workout, at: 0)
        active = nil
        automaticPauseActive = false
        autoPauseDetector.reset(enabled: false)
        manager.distanceFilter = 5
        resetRouteRuntime()
        persistActiveCheckpoint(force: true)
        persistHistory()

        if workout
            .audioCoachConfiguration?
            .enabled == true,
           workout
            .audioCoachConfiguration?
            .shouldAnnounceWorkoutComplete == true {
            speak(
                localizedCoachPhrase(
                    english: "Workout complete.",
                    norwegian: "Økten er fullført.",
                    configuration:
                        workout
                            .audioCoachConfiguration
                ),
                configuration:
                    workout
                        .audioCoachConfiguration,
                priority:
                    .structuredStep
            )
        } else {
            deactivateCoachAudioSession()
        }

        // Publish a stable pre-save completion checkpoint. The app captures
        // Goals/Challenge/Gear state here, before HealthKit can change the
        // workout identity or downstream progress.
        completionStartedWorkout = workout

        await saveToHealth(
            workout,
            userID: userID
        )

        // Emit completion only after the Health save attempt has settled so
        // downstream Goals, Challenges and the review all see the final
        // HealthKit workout identity when one is available.
        lastCompletedWorkout =
            history.first(
                where: {
                    $0.id == workout.id
                }
            ) ?? workout
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

            await syncRouteAttemptIfNeeded(
                workout: workout,
                healthWorkoutID: saved.uuid,
                userID: userID
            )

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

        if workout.resumedAt != nil {
            evaluateStructuredWorkout(
                &workout
            )
            evaluateCoachAnnouncements(
                workout
            )
        }

        active = workout
        persistActiveCheckpoint(force: true)
        syncLiveActivity()
    }

    var currentStructuredStep:
        WatchRunningWorkoutStep?
    {
        guard let workout = active,
              let plan =
                workout.structuredRunningWorkout,
              plan.steps.indices.contains(
                workout.structuredStepIndex ?? 0
              )
        else {
            return nil
        }

        return plan.steps[
            workout.structuredStepIndex ?? 0
        ]
    }

    var nextStructuredStep:
        WatchRunningWorkoutStep?
    {
        guard let workout = active,
              let plan =
                workout.structuredRunningWorkout
        else {
            return nil
        }

        let next =
            (workout.structuredStepIndex ?? 0) + 1

        return plan.steps.indices.contains(next)
            ? plan.steps[next]
            : nil
    }

    func currentStructuredStepProgress(
        at date: Date = Date()
    ) -> Double {
        guard let workout = active,
              let step = currentStructuredStep
        else {
            return 0
        }

        return ATHLTHRunningStepEngine
            .progress(
                step: step,
                elapsedTime:
                    workout.elapsed(at: date),
                distanceMeters:
                    workout.distanceMeters,
                stepStartElapsedTime:
                    workout
                        .structuredStepStartElapsedTime ??
                    0,
                stepStartDistanceMeters:
                    workout
                        .structuredStepStartDistanceMeters ??
                    0
            )
    }

    func applyGhostComparison(
        _ comparison: GhostRaceComparison?,
        title: String?,
        configuration:
            WatchGhostRaceAudioConfiguration?
    ) {
        guard var workout = active,
              !workout.walking
        else {
            return
        }

        if let configuration {
            workout.ghostAudioConfiguration =
                configuration
        }

        guard let comparison else {
            workout.ghostRaceTitle = nil
            workout.ghostDistanceDeltaMeters = nil
            workout.ghostTimeDeltaSeconds = nil
            active = workout
            return
        }

        workout.ghostRaceTitle =
            title ?? "Ghost"
        workout.ghostDistanceDeltaMeters =
            comparison.signedDistanceMeters
        workout.ghostTimeDeltaSeconds =
            comparison.signedTimeSeconds

        evaluateGhostUpdates(
            workout: workout,
            distanceDelta:
                comparison.signedDistanceMeters,
            timeDelta:
                comparison.signedTimeSeconds
        )

        active = workout
        persistActiveCheckpoint()
        syncLiveActivity()
    }

    func applyLiveGhostUpdate(
        title: String,
        distanceDelta: Double,
        timeDelta: TimeInterval?,
        configuration:
            WatchGhostRaceAudioConfiguration?
    ) {
        guard var workout = active,
              !workout.walking
        else {
            return
        }

        workout.ghostRaceTitle = title
        workout.ghostDistanceDeltaMeters =
            distanceDelta
        workout.ghostTimeDeltaSeconds =
            timeDelta
        if let configuration {
            workout.ghostAudioConfiguration =
                configuration
        }

        evaluateGhostUpdates(
            workout: workout,
            distanceDelta: distanceDelta,
            timeDelta: timeDelta
        )

        active = workout
        persistActiveCheckpoint()
        syncLiveActivity()
    }

    private func cachePlannedRouteGeometry(
        _ route: TrainingRoute?
    ) {
        guard let route,
              route.coordinates.count >= 2
        else {
            plannedRouteLocations = []
            plannedRouteCumulativeMeters = []
            plannedRouteGeometryMeters = 0
            return
        }

        let locations =
            route.coordinates
                .sorted {
                    $0.sequence < $1.sequence
                }
                .map {
                    CLLocation(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                }

        let geometry =
            ATHLTHRouteGuidanceEngine
                .cumulativeGeometry(
                    locations: locations
                )

        plannedRouteLocations = locations
        plannedRouteCumulativeMeters =
            geometry.cumulativeMeters
        plannedRouteGeometryMeters =
            geometry.totalMeters
    }

    private func restoreRouteGeometry(
        from workout: PhoneWorkout
    ) {
        guard plannedRouteLocations.isEmpty,
              let coordinates =
                workout.plannedRouteCoordinates,
              coordinates.count >= 2
        else {
            return
        }

        let locations =
            coordinates
                .sorted {
                    $0.sequence < $1.sequence
                }
                .map {
                    CLLocation(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                }
        let geometry =
            ATHLTHRouteGuidanceEngine
                .cumulativeGeometry(
                    locations: locations
                )

        plannedRouteLocations = locations
        plannedRouteCumulativeMeters =
            geometry.cumulativeMeters
        plannedRouteGeometryMeters =
            geometry.totalMeters
    }

    private func resetRouteRuntime() {
        plannedRouteLocations = []
        plannedRouteCumulativeMeters = []
        plannedRouteGeometryMeters = 0
        nextDistanceAnnouncementMeters = nil
        nextTimeAnnouncementSeconds = nil
        resetRouteAlertRuntime()
        resetGhostRuntime(
            configuration: nil
        )
        guidancePriorityGate.reset()
        speechSynthesizer.stopSpeaking(
            at: .immediate
        )
    }

    private func resetCoachThresholds(
        configuration:
            WatchAudioCoachConfiguration?
    ) {
        guard let configuration,
              configuration.enabled
        else {
            nextDistanceAnnouncementMeters = nil
            nextTimeAnnouncementSeconds = nil
            return
        }

        if let interval =
                configuration.distanceIntervalMeters,
           interval > 0 {
            nextDistanceAnnouncementMeters =
                interval
        } else {
            nextDistanceAnnouncementMeters = nil
        }

        if let interval =
                configuration.timeIntervalSeconds,
           interval > 0 {
            nextTimeAnnouncementSeconds =
                interval
        } else {
            nextTimeAnnouncementSeconds = nil
        }
    }

    private func resetRouteAlertRuntime() {
        offRouteStartedAt = nil
        lastOffRouteAlertAt = nil
        routeWasOff = false
    }

    private func resetGhostRuntime(
        configuration:
            WatchGhostRaceAudioConfiguration?
    ) {
        lastGhostAnnouncedLeadMeters = nil
        lastGhostLeadAlertAt = nil
        lastGhostLeadSign = 0

        if let interval =
                configuration?
                    .distanceIntervalMeters,
           interval > 0 {
            nextGhostDistanceAnnouncementMeters =
                interval
        } else {
            nextGhostDistanceAnnouncementMeters =
                nil
        }

        if let interval =
                configuration?
                    .timeIntervalSeconds,
           interval > 0 {
            nextGhostTimeAnnouncementSeconds =
                interval
        } else {
            nextGhostTimeAnnouncementSeconds =
                nil
        }
    }


    private func updatePace(
        workout: inout PhoneWorkout,
        location: CLLocation
    ) {
        guard location.speed >= 0.35 else {
            return
        }

        let rawPace =
            1_000 / location.speed

        guard rawPace >= 120,
              rawPace <= 1_800
        else {
            return
        }

        if let existing =
            workout
                .currentPaceSecondsPerKilometer {
            workout
                .currentPaceSecondsPerKilometer =
                    existing * 0.72 +
                    rawPace * 0.28
        } else {
            workout
                .currentPaceSecondsPerKilometer =
                    rawPace
        }
    }

    private func updateRouteGuidance(
        workout: inout PhoneWorkout,
        location: CLLocation
    ) {
        restoreRouteGeometry(
            from: workout
        )

        guard let guidance =
                ATHLTHRouteGuidanceEngine.state(
                    location: location,
                    routeLocations:
                        plannedRouteLocations,
                    cumulativeMeters:
                        plannedRouteCumulativeMeters,
                    geometryTotalMeters:
                        plannedRouteGeometryMeters,
                    advertisedDistanceMeters:
                        workout
                            .plannedRouteDistanceKilometers
                            .map { $0 * 1_000 }
                )
        else {
            return
        }

        workout.routeProgressPercent =
            guidance.progressPercent
        workout.routeRemainingMeters =
            guidance.remainingMeters
        workout.routeDeviationMeters =
            guidance.deviationMeters
        workout.routeDistanceToStartMeters =
            guidance.distanceToStartMeters
        workout.routeDistanceToFinishMeters =
            guidance.distanceToFinishMeters
        workout.routeNextBearingDegrees =
            nextBearing(
                from: location,
                nearestIndex:
                    guidance
                        .nearestRoutePointIndex
            )

        evaluateRouteAlert(
            workout: workout,
            deviationMeters:
                guidance.deviationMeters,
            horizontalAccuracy:
                location.horizontalAccuracy
        )
    }

    private func nextBearing(
        from location: CLLocation,
        nearestIndex: Int
    ) -> Double? {
        guard !plannedRouteLocations.isEmpty else {
            return nil
        }

        let nextIndex =
            min(
                nearestIndex + 1,
                plannedRouteLocations.count - 1
            )
        let next =
            plannedRouteLocations[nextIndex]

        guard nextIndex != nearestIndex else {
            return nil
        }

        let latitude1 =
            location.coordinate.latitude *
            .pi / 180
        let latitude2 =
            next.coordinate.latitude *
            .pi / 180
        let longitudeDelta =
            (
                next.coordinate.longitude -
                location.coordinate.longitude
            ) * .pi / 180

        let y =
            sin(longitudeDelta) *
            cos(latitude2)
        let x =
            cos(latitude1) *
                sin(latitude2) -
            sin(latitude1) *
                cos(latitude2) *
                cos(longitudeDelta)
        let degrees =
            atan2(y, x) *
            180 / .pi

        return (
            degrees + 360
        ).truncatingRemainder(
            dividingBy: 360
        )
    }

    private func evaluateGhostUpdates(
        workout: PhoneWorkout,
        distanceDelta: Double,
        timeDelta: TimeInterval?
    ) {
        guard let configuration =
                workout.ghostAudioConfiguration,
              configuration.enabled,
              workout.resumedAt != nil
        else {
            return
        }

        var periodic = false

        if let interval =
                configuration.distanceIntervalMeters,
           interval > 0,
           let next =
                nextGhostDistanceAnnouncementMeters,
           workout.distanceMeters >= next {
            periodic = true
            var updatedNext = next
            repeat {
                updatedNext += interval
            } while workout.distanceMeters >=
                updatedNext
            nextGhostDistanceAnnouncementMeters =
                updatedNext
        }

        let elapsed =
            workout.elapsed(at: Date())

        if let interval =
                configuration.timeIntervalSeconds,
           interval > 0,
           let next =
                nextGhostTimeAnnouncementSeconds,
           elapsed >= next {
            periodic = true
            var updatedNext = next
            repeat {
                updatedNext += interval
            } while elapsed >= updatedNext
            nextGhostTimeAnnouncementSeconds =
                updatedNext
        }

        if periodic {
            deliverGhostUpdate(
                distanceDelta: distanceDelta,
                timeDelta: timeDelta,
                delivery:
                    configuration
                        .resolvedPeriodicDelivery,
                priority:
                    .ghostPeriodic,
                workout: workout
            )
            lastGhostAnnouncedLeadMeters =
                distanceDelta
            lastGhostLeadAlertAt = Date()
            lastGhostLeadSign =
                ghostLeadSign(
                    distanceDelta
                )
            return
        }

        guard configuration
                .announceLeadChanges,
              elapsed >= 20
        else {
            return
        }

        let currentSign =
            ghostLeadSign(distanceDelta)
        let signChanged =
            currentSign != 0 &&
            lastGhostLeadSign != 0 &&
            currentSign != lastGhostLeadSign
        let change =
            lastGhostAnnouncedLeadMeters.map {
                abs(distanceDelta - $0)
            } ?? 0
        let movedEnough =
            change >=
            max(
                configuration
                    .leadChangeThresholdMeters,
                10
            )
        let cooldownSatisfied =
            lastGhostLeadAlertAt.map {
                Date().timeIntervalSince($0) >=
                    30
            } ?? true

        guard cooldownSatisfied &&
                (signChanged || movedEnough)
        else {
            if lastGhostAnnouncedLeadMeters ==
                nil {
                lastGhostAnnouncedLeadMeters =
                    distanceDelta
                lastGhostLeadSign =
                    currentSign
            }
            return
        }

        let important =
            signChanged ||
            change >=
                configuration
                    .resolvedImportantLeadChangeMeters

        deliverGhostUpdate(
            distanceDelta: distanceDelta,
            timeDelta: timeDelta,
            delivery:
                important
                    ? configuration
                        .resolvedImportantLeadChangeDelivery
                    : configuration
                        .resolvedLeadChangeDelivery,
            priority:
                important
                    ? .ghostImportant
                    : .ghostPeriodic,
            workout: workout
        )

        lastGhostAnnouncedLeadMeters =
            distanceDelta
        lastGhostLeadAlertAt = Date()
        lastGhostLeadSign = currentSign
    }

    private func deliverGhostUpdate(
        distanceDelta: Double,
        timeDelta: TimeInterval?,
        delivery: WatchAlertDelivery,
        priority: ATHLTHGuidancePriority,
        workout: PhoneWorkout
    ) {
        let meters = abs(distanceDelta)
        let english: String
        let norwegian: String

        if meters < 8 {
            english =
                "Ghost Race. Neck and neck."
            norwegian =
                "Spøkelsesløp. Helt jevnt."
        } else if distanceDelta > 0 {
            var englishParts = [
                "Ghost Race. You are " +
                    routeDistancePhrase(meters) +
                    " ahead."
            ]
            var norwegianParts = [
                "Spøkelsesløp. Du er " +
                    routeDistancePhrase(meters) +
                    " foran."
            ]

            if let timeDelta {
                englishParts.append(
                    "About " +
                    durationPhrase(
                        abs(timeDelta)
                    ) +
                    " ahead."
                )
                norwegianParts.append(
                    "Omtrent " +
                    durationPhrase(
                        abs(timeDelta)
                    ) +
                    " foran."
                )
            }

            english =
                englishParts.joined(
                    separator: " "
                )
            norwegian =
                norwegianParts.joined(
                    separator: " "
                )
        } else {
            var englishParts = [
                "Ghost Race. Your ghost is " +
                    routeDistancePhrase(meters) +
                    " ahead."
            ]
            var norwegianParts = [
                "Spøkelsesløp. Spøkelset er " +
                    routeDistancePhrase(meters) +
                    " foran."
            ]

            if let timeDelta {
                englishParts.append(
                    "About " +
                    durationPhrase(
                        abs(timeDelta)
                    ) +
                    " behind."
                )
                norwegianParts.append(
                    "Omtrent " +
                    durationPhrase(
                        abs(timeDelta)
                    ) +
                    " bak."
                )
            }

            english =
                englishParts.joined(
                    separator: " "
                )
            norwegian =
                norwegianParts.joined(
                    separator: " "
                )
        }

        deliverPhoneGuidanceAlert(
            english: english,
            norwegian: norwegian,
            delivery: delivery,
            haptic:
                distanceDelta >= 0
                    ? .success
                    : .warning,
            priority: priority,
            coachConfiguration:
                workout.audioCoachConfiguration
        )
    }

    private func ghostLeadSign(
        _ distanceDelta: Double
    ) -> Int {
        if abs(distanceDelta) < 8 {
            return 0
        }

        return distanceDelta > 0 ? 1 : -1
    }

    private func routeDistancePhrase(
        _ meters: Double
    ) -> String {
        if meters >= 1_000 {
            return String(
                format:
                    "%.1f kilometers",
                meters / 1_000
            )
        }

        return
            "\(Int(meters.rounded())) meters"
    }

    private func evaluateRouteAlert(
        workout: PhoneWorkout,
        deviationMeters: Double,
        horizontalAccuracy: Double
    ) {
        guard let configuration =
                workout.routeAlertConfiguration,
              configuration.enabled,
              horizontalAccuracy >= 0,
              horizontalAccuracy <= 50
        else {
            offRouteStartedAt = nil
            return
        }

        let now = Date()
        let isOffRoute =
            deviationMeters >
            configuration.deviationMeters

        guard isOffRoute else {
            offRouteStartedAt = nil
            lastOffRouteAlertAt = nil

            if routeWasOff {
                routeWasOff = false

                if configuration
                    .announceBackOnRoute {
                    deliverRouteAlert(
                        configuration:
                            configuration,
                        english:
                            "Back on route.",
                        norwegian:
                            "Tilbake på ruten.",
                        haptic: .success
                    )
                }
            }

            return
        }

        if offRouteStartedAt == nil {
            offRouteStartedAt = now
        }

        guard now.timeIntervalSince(
            offRouteStartedAt ?? now
        ) >= configuration.graceSeconds
        else {
            return
        }

        if let lastOffRouteAlertAt,
           now.timeIntervalSince(
                lastOffRouteAlertAt
           ) < configuration.repeatSeconds {
            return
        }

        routeWasOff = true
        lastOffRouteAlertAt = now

        deliverRouteAlert(
            configuration: configuration,
            english:
                "You are off route. " +
                "\(Int(deviationMeters.rounded())) meters.",
            norwegian:
                "Du er utenfor ruten. " +
                "\(Int(deviationMeters.rounded())) meter.",
            haptic: .warning
        )
    }

    private func deliverRouteAlert(
        configuration:
            WatchRouteAlertConfiguration,
        english: String,
        norwegian: String,
        haptic:
            UINotificationFeedbackGenerator
                .FeedbackType
    ) {
        deliverPhoneGuidanceAlert(
            english: english,
            norwegian: norwegian,
            delivery:
                configuration.delivery,
            haptic: haptic,
            priority:
                .routeCritical,
            coachConfiguration:
                active?
                    .audioCoachConfiguration
        )
    }

    private func deliverPhoneGuidanceAlert(
        english: String,
        norwegian: String,
        delivery: WatchAlertDelivery,
        haptic:
            UINotificationFeedbackGenerator
                .FeedbackType,
        priority:
            ATHLTHGuidancePriority,
        coachConfiguration:
            WatchAudioCoachConfiguration?
    ) {
        let deliveryPreferences =
            ATHLTHLiveWorkoutPreferencesStore
                .load()

        if delivery.usesHaptics,
           deliveryPreferences
                .hapticsEnabled,
           guidancePriorityGate
            .allowsHaptic(
                for: priority
            ) {
            UINotificationFeedbackGenerator()
                .notificationOccurred(haptic)
        }

        if delivery.usesVoice,
           deliveryPreferences
                .audioAlertsEnabled {
            let phrase =
                localizedCoachPhrase(
                    english: english,
                    norwegian: norwegian,
                    configuration:
                        coachConfiguration
                )

            speak(
                phrase,
                configuration:
                    coachConfiguration,
                priority: priority
            )
        }
    }

    private func localizedCoachPhrase(
        english: String,
        norwegian: String,
        configuration:
            WatchAudioCoachConfiguration?
    ) -> String {
        switch configuration?.language {
        case .norwegian:
            return norwegian
        case .english:
            return english
        case .system, .none:
            let code =
                Locale.current.language
                    .languageCode?
                    .identifier
                    .lowercased()
            return code == "nb" ||
                code == "nn" ||
                code == "no"
                ? norwegian
                : english
        }
    }

    private func evaluateStructuredWorkout(
        _ workout: inout PhoneWorkout
    ) {
        guard workout.structuredWorkoutComplete != true,
              let plan =
                workout.structuredRunningWorkout,
              plan.steps.indices.contains(
                workout.structuredStepIndex ?? 0
              )
        else {
            return
        }

        let step =
            plan.steps[
                workout.structuredStepIndex ?? 0
            ]

        guard ATHLTHRunningStepEngine
            .isCompleted(
                step: step,
                elapsedTime:
                    workout.elapsed(at: Date()),
                distanceMeters:
                    workout.distanceMeters,
                stepStartElapsedTime:
                    workout
                        .structuredStepStartElapsedTime ??
                    0,
                stepStartDistanceMeters:
                    workout
                        .structuredStepStartDistanceMeters ??
                    0
            )
        else {
            return
        }

        let nextIndex =
            (workout.structuredStepIndex ?? 0) + 1

        guard plan.steps.indices.contains(
            nextIndex
        ) else {
            workout.structuredWorkoutComplete = true
            UINotificationFeedbackGenerator()
                .notificationOccurred(.success)

            if workout
                .audioCoachConfiguration?
                .enabled == true {
                speak(
                    "Structured workout complete. Continue easy or finish when ready.",
                    configuration:
                        workout.audioCoachConfiguration,
                    priority:
                        .structuredStep
                )
            }
            return
        }

        workout.structuredStepIndex =
            nextIndex
        workout.structuredStepStartElapsedTime =
            workout.elapsed(at: Date())
        workout.structuredStepStartDistanceMeters =
            workout.distanceMeters

        UINotificationFeedbackGenerator()
            .notificationOccurred(.success)

        if workout
            .audioCoachConfiguration?
            .announceCurrentWorkoutStep == true {
            let next =
                plan.steps[nextIndex]
            speak(
                "Next. \(next.title).",
                configuration:
                    workout.audioCoachConfiguration,
                priority:
                    .structuredStep
            )
        }
    }

    private func announceStructuredStepIfNeeded(
        prefix: String
    ) {
        guard let workout = active,
              workout
                .audioCoachConfiguration?
                .enabled == true,
              workout
                .audioCoachConfiguration?
                .announceCurrentWorkoutStep == true,
              let plan =
                workout.structuredRunningWorkout,
              plan.steps.indices.contains(
                workout.structuredStepIndex ?? 0
              )
        else {
            return
        }

        speak(
            "\(prefix). \(plan.steps[workout.structuredStepIndex ?? 0].title).",
            configuration:
                workout.audioCoachConfiguration,
            priority:
                .structuredStep
        )
    }

    private func evaluateCoachAnnouncements(
        _ workout: PhoneWorkout
    ) {
        guard let configuration =
                workout.audioCoachConfiguration,
              configuration.enabled
        else {
            return
        }

        var shouldAnnounce = false

        if let interval =
                configuration.distanceIntervalMeters,
           interval > 0,
           let next =
                nextDistanceAnnouncementMeters,
           workout.distanceMeters >= next {
            repeat {
                nextDistanceAnnouncementMeters =
                    (
                        nextDistanceAnnouncementMeters ??
                        next
                    ) + interval
            } while workout.distanceMeters >=
                (
                    nextDistanceAnnouncementMeters ??
                    .greatestFiniteMagnitude
                )
            shouldAnnounce = true
        }

        let elapsed =
            workout.elapsed(at: Date())

        if let interval =
                configuration.timeIntervalSeconds,
           interval > 0,
           let next =
                nextTimeAnnouncementSeconds,
           elapsed >= next {
            repeat {
                nextTimeAnnouncementSeconds =
                    (
                        nextTimeAnnouncementSeconds ??
                        next
                    ) + interval
            } while elapsed >=
                (
                    nextTimeAnnouncementSeconds ??
                    .greatestFiniteMagnitude
                )
            shouldAnnounce = true
        }

        guard shouldAnnounce else {
            return
        }

        var parts: [String] = []

        if configuration.announceDistance {
            parts.append(
                String(
                    format:
                        "%.1f kilometers",
                    workout.distanceMeters /
                        1_000
                )
            )
        }

        if configuration.announceElapsedTime {
            parts.append(
                durationPhrase(elapsed)
            )
        }

        if configuration.announceAveragePace,
           workout.distanceMeters >= 100 {
            let pace =
                elapsed /
                (
                    workout.distanceMeters /
                    1_000
                )
            parts.append(
                "average pace \(pacePhrase(pace))"
            )
        }

        if configuration
            .announceRemainingRouteDistance,
           let remaining =
                workout.routeRemainingMeters {
            parts.append(
                remaining < 1_000
                    ? "\(Int(remaining.rounded())) meters remaining"
                    : String(
                        format:
                            "%.1f kilometers remaining",
                        remaining / 1_000
                    )
            )
        }

        if configuration
            .announceEstimatedRemainingRouteTime,
           let remaining =
                workout.routeRemainingMeters,
           let pace =
                workout
                    .currentPaceSecondsPerKilometer,
           pace > 0 {
            parts.append(
                "about \(durationPhrase((remaining / 1_000) * pace)) remaining"
            )
        }

        if configuration.announceClockTime {
            parts.append(
                Date().formatted(
                    date: .omitted,
                    time: .shortened
                )
            )
        }

        guard !parts.isEmpty else {
            return
        }

        speak(
            parts.joined(
                separator: ". "
            ),
            configuration: configuration,
            priority:
                .routineCoach
        )
    }

    private func speak(
        _ phrase: String,
        configuration:
            WatchAudioCoachConfiguration?,
        priority:
            ATHLTHGuidancePriority =
                .routineCoach
    ) {
        guard !phrase.isEmpty else {
            return
        }

        let configuration =
            configuration ??
            .disabled
        let decision =
            guidancePriorityGate
                .voiceDecision(
                    for: priority,
                    isSpeaking:
                        speechSynthesizer
                            .isSpeaking,
                    quietPeriodSeconds:
                        configuration
                            .resolvedGuidanceQuietPeriodSeconds
                )

        switch decision {
        case .drop:
            return
        case .interruptAndDeliver:
            speechSynthesizer
                .stopSpeaking(
                    at: .immediate
                )
        case .deliver:
            break
        }

        do {
            let session =
                AVAudioSession.sharedInstance()
            let options:
                AVAudioSession.CategoryOptions =
                    configuration
                        .shouldDuckOtherAudio
                        ? [.duckOthers]
                        : [.mixWithOthers]
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: options
            )
            try session.setActive(true)
        } catch {
            // Speech remains best-effort and must never stop the workout.
        }

        let utterance =
            AVSpeechUtterance(
                string: phrase
            )

        if let voiceIdentifier =
                configuration
                    .voiceIdentifier,
           let selectedVoice =
                AVSpeechSynthesisVoice(
                    identifier:
                        voiceIdentifier
                ) {
            utterance.voice = selectedVoice
        } else {
            switch configuration.language {
            case .english:
                utterance.voice =
                    AVSpeechSynthesisVoice(
                        language: "en-US"
                    )
            case .norwegian:
                utterance.voice =
                    AVSpeechSynthesisVoice(
                        language: "nb-NO"
                    )
            case .system:
                break
            }
        }

        utterance.rate =
            configuration
                .resolvedSpeechRate
        utterance.volume =
            configuration
                .resolvedSpeechVolume

        speechSynthesizer.speak(utterance)
    }

    private func deactivateCoachAudioSession() {
        speechSynthesizer.stopSpeaking(
            at: .immediate
        )

        try? AVAudioSession
            .sharedInstance()
            .setActive(
                false,
                options:
                    .notifyOthersOnDeactivation
            )
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.speechSynthesizer.isSpeaking
            else {
                return
            }

            self.guidancePriorityGate.voiceDidFinish()

            try? AVAudioSession
                .sharedInstance()
                .setActive(
                    false,
                    options:
                        .notifyOthersOnDeactivation
                )
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.speechSynthesizer.isSpeaking
            else {
                return
            }

            self.guidancePriorityGate.voiceDidFinish()

            try? AVAudioSession
                .sharedInstance()
                .setActive(
                    false,
                    options:
                        .notifyOthersOnDeactivation
                )
        }
    }

    private func durationPhrase(
        _ seconds: TimeInterval
    ) -> String {
        let totalMinutes =
            max(
                Int(
                    (seconds / 60)
                        .rounded()
                ),
                0
            )
        let hours =
            totalMinutes / 60
        let minutes =
            totalMinutes % 60

        if hours > 0 {
            return minutes > 0
                ? "\(hours) hours \(minutes) minutes"
                : "\(hours) hours"
        }

        return "\(minutes) minutes"
    }

    private func pacePhrase(
        _ seconds: TimeInterval
    ) -> String {
        let total =
            max(
                Int(seconds.rounded()),
                0
            )
        return String(
            format:
                "%d minutes %02d seconds per kilometer",
            total / 60,
            total % 60
        )
    }

    private func syncRouteAttemptIfNeeded(
        workout: PhoneWorkout,
        healthWorkoutID: UUID,
        userID: UUID
    ) async {
        guard let routeID =
                workout
                    .plannedComparisonRouteID ??
                workout.plannedRouteID,
              let coordinates =
                workout.plannedRouteCoordinates,
              coordinates.count >= 2
        else {
            return
        }

        let actual =
            workout.points
                .filter {
                    $0.accuracy >= 0 &&
                    $0.accuracy <= 65
                }
                .map(\.location)
        let reference =
            coordinates
                .sorted {
                    $0.sequence < $1.sequence
                }
                .map {
                    CLLocation(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                }

        guard let match =
                ATHLTHRouteCompletionAnalyzer
                    .analyze(
                        actualLocations: actual,
                        referenceLocations:
                            reference
                    )
        else {
            return
        }

        let routeMeters =
            max(
                (
                    workout
                        .plannedRouteDistanceKilometers ??
                    0
                ) * 1_000,
                1
            )
        let ratio =
            workout.distanceMeters /
            routeMeters

        guard match.routeMatchPercent >= 60,
              match.startDistanceMeters <= 450,
              match.endDistanceMeters <= 450,
              ratio >= 0.55,
              ratio <= 1.55
        else {
            return
        }

        let analysis =
            RoutePerformanceAnalysis(
                workoutID: healthWorkoutID,
                activity:
                    workout.walking
                        ? .walking
                        : .running,
                startedAt: workout.start,
                durationSeconds:
                    workout.accumulatedSeconds,
                distanceMeters:
                    workout.distanceMeters,
                routeMatchPercent:
                    match.routeMatchPercent,
                averageDeviationMeters:
                    match
                        .averageDeviationMeters,
                maxDeviationMeters:
                    match.maxDeviationMeters,
                startDistanceMeters:
                    match.startDistanceMeters,
                endDistanceMeters:
                    match.endDistanceMeters
            )

        do {
            let attempts:
                [RouteAttemptRecord]

            if workout.plannedRouteSource ==
                "openstreetmap" {
                let service =
                    SupabasePublicTrailAttemptService()
                try await service.upsert(
                    trailID: routeID,
                    userID: userID,
                    analysis: analysis
                )
                attempts =
                    try await service.load(
                        trailID: routeID
                    )
            } else {
                let service =
                    SupabaseRouteAttemptService()
                try await service.upsert(
                    routeID: routeID,
                    userID: userID,
                    analysis: analysis
                )
                attempts =
                    try await service.load(
                        routeID: routeID
                    )
            }

            updateLeaderboardRank(
                attempts: attempts,
                userID: userID,
                currentWorkoutID:
                    healthWorkoutID
            )
        } catch {
            // The workout and Health save are authoritative. Leaderboard
            // upload retries naturally when route details sync Health later.
        }
    }

    private func updateLeaderboardRank(
        attempts: [RouteAttemptRecord],
        userID: UUID,
        currentWorkoutID: UUID
    ) {
        let eligible =
            attempts
                .filter(\.leaderboardEligible)

        var bestByUser:
            [UUID: RouteAttemptRecord] = [:]

        for attempt in eligible {
            if let current =
                bestByUser[attempt.userID] {
                if attempt.durationSeconds <
                    current.durationSeconds {
                    bestByUser[
                        attempt.userID
                    ] = attempt
                }
            } else {
                bestByUser[
                    attempt.userID
                ] = attempt
            }
        }

        let ordered =
            bestByUser.values.sorted {
                if abs(
                    $0.durationSeconds -
                    $1.durationSeconds
                ) > 0.1 {
                    return $0.durationSeconds <
                        $1.durationSeconds
                }

                return $0.routeMatchPercent >
                    $1.routeMatchPercent
            }

        guard let rank =
                ordered.firstIndex(
                    where: {
                        $0.userID == userID
                    }
                )
        else {
            return
        }

        if var completion =
            lastRouteCompletion {
            completion.leaderboardRank =
                rank + 1
            completion.leaderboardFieldSize =
                ordered.count

            let userBest =
                attempts
                    .filter {
                        $0.userID == userID &&
                        $0.leaderboardEligible
                    }
                    .min {
                        $0.durationSeconds <
                            $1.durationSeconds
                    }

            completion.personalBest =
                userBest?.workoutID ==
                currentWorkoutID

            lastRouteCompletion =
                completion
        }
    }

    private func routeCompletionSummary(
        for workout: PhoneWorkout
    ) -> PhoneRouteCompletionSummary? {
        guard let routeID =
                workout.plannedRouteID,
              let routeTitle =
                workout.plannedRouteTitle,
              let coordinates =
                workout.plannedRouteCoordinates,
              coordinates.count >= 2
        else {
            return nil
        }

        let actual =
            workout.points
                .filter {
                    $0.accuracy >= 0 &&
                    $0.accuracy <= 65
                }
                .map(\.location)
        let reference =
            coordinates
                .sorted {
                    $0.sequence < $1.sequence
                }
                .map {
                    CLLocation(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                }

        guard let analysis =
                ATHLTHRouteCompletionAnalyzer
                    .analyze(
                        actualLocations: actual,
                        referenceLocations:
                            reference
                    )
        else {
            return nil
        }

        let duration =
            workout.accumulatedSeconds
        let previousBest =
            history
                .filter {
                    $0.plannedRouteID ==
                        routeID &&
                    $0.finalLeaderboardEligible ==
                        true
                }
                .map(\.accumulatedSeconds)
                .filter { $0 > 0 }
                .min()

        let personalBest =
            analysis.leaderboardEligible &&
            (
                previousBest == nil ||
                duration <
                    (previousBest ??
                        .greatestFiniteMagnitude)
            )

        return PhoneRouteCompletionSummary(
            routeID: routeID,
            routeTitle: routeTitle,
            routeMatchPercent:
                analysis.routeMatchPercent,
            averageDeviationMeters:
                analysis
                    .averageDeviationMeters,
            maxDeviationMeters:
                analysis.maxDeviationMeters,
            distanceMeters:
                workout.distanceMeters,
            durationSeconds: duration,
            leaderboardEligible:
                analysis.leaderboardEligible,
            personalBest: personalBest
        )
    }

    func currentLiveSnapshot()
        -> WatchWorkoutLiveSnapshot?
    {
        guard let workout = active else {
            return nil
        }

        let latest =
            workout.points.last

        return WatchWorkoutLiveSnapshot(
            kind:
                workout.walking
                    ? .walking
                    : .running,
            state:
                workout.resumedAt == nil
                    ? .paused
                    : .running,
            startedAt: workout.start,
            capturedAt: Date(),
            elapsedTime:
                workout.elapsed(at: Date()),
            heartRate: 0,
            activeCalories: 0,
            distanceMeters:
                workout.distanceMeters,
            averageHeartRate: nil,
            maxHeartRate: nil,
            routePointCount:
                workout.points.count,
            currentLatitude:
                latest?.latitude,
            currentLongitude:
                latest?.longitude,
            routeProgressPercent:
                workout.routeProgressPercent,
            routeComparisonID:
                workout
                    .plannedComparisonRouteID ??
                workout.plannedRouteID,
            routeTitle:
                workout.plannedRouteTitle,
            routeDistanceMeters:
                workout
                    .plannedRouteDistanceKilometers
                    .map { $0 * 1_000 },
            workoutDisplayTitle:
                workout.title,
            currentPaceSecondsPerKilometer:
                workout
                    .currentPaceSecondsPerKilometer,
            routeRemainingMeters:
                workout.routeRemainingMeters,
            routeDeviationMeters:
                workout.routeDeviationMeters,
            routeDeviationThresholdMeters:
                workout
                    .routeAlertConfiguration?
                    .deviationMeters,
            ghostRaceTitle:
                workout.ghostRaceTitle,
            ghostDistanceDeltaMeters:
                workout
                    .ghostDistanceDeltaMeters,
            ghostTimeDeltaSeconds:
                workout
                    .ghostTimeDeltaSeconds,
            liveSurfaceConfiguration:
                ATHLTHLiveWorkoutPreferencesStore
                    .load(),
            liveSurfaceContext:
                ATHLTHLiveWorkoutContextStore
                    .load()
        )
    }

    private func syncLiveActivity() {
        guard let workout = active else {
            return
        }

        syncLiveActivity(
            workout: workout,
            state:
                workout.resumedAt == nil
                    ? .paused
                    : .running
        )
    }

    private func syncLiveActivity(
        workout: PhoneWorkout,
        state: WatchWorkoutMirrorState
    ) {
        let latest =
            workout.points.last
        let currentStep:
            WatchRunningWorkoutStep? = {
            guard let plan =
                    workout
                        .structuredRunningWorkout,
                  plan.steps.indices.contains(
                    workout.structuredStepIndex ?? 0
                  )
            else {
                return nil
            }

            return plan.steps[
                workout.structuredStepIndex ?? 0
            ]
        }()
        let runningStepProgress =
            currentStep.map {
                ATHLTHRunningStepEngine
                    .progress(
                        step: $0,
                        elapsedTime:
                            workout.elapsed(
                                at: Date()
                            ),
                        distanceMeters:
                            workout.distanceMeters,
                        stepStartElapsedTime:
                            workout
                                .structuredStepStartElapsedTime ??
                            0,
                        stepStartDistanceMeters:
                            workout
                                .structuredStepStartDistanceMeters ??
                            0
                    )
            }
        let nextStepTitle: String? = {
            guard let plan =
                    workout
                        .structuredRunningWorkout
            else {
                return nil
            }

            let next =
                (workout.structuredStepIndex ?? 0) + 1
            return plan.steps.indices.contains(
                next
            )
                ? plan.steps[next].title
                : nil
        }()

        let snapshot =
            WatchWorkoutLiveSnapshot(
                kind:
                    workout.walking
                        ? .walking
                        : .running,
                state: state,
                startedAt:
                    workout.start,
                capturedAt: Date(),
                elapsedTime:
                    workout.elapsed(at: Date()),
                heartRate: 0,
                activeCalories: 0,
                distanceMeters:
                    workout.distanceMeters,
                averageHeartRate: nil,
                maxHeartRate: nil,
                routePointCount:
                    workout.points.count,
                currentLatitude:
                    latest?.latitude,
                currentLongitude:
                    latest?.longitude,
                routeProgressPercent:
                    workout.routeProgressPercent,
                routeComparisonID:
                    workout
                        .plannedComparisonRouteID ??
                    workout.plannedRouteID,
                routeTitle:
                    workout.plannedRouteTitle,
                routeDistanceMeters:
                    workout
                        .plannedRouteDistanceKilometers
                        .map { $0 * 1_000 },
                workoutDisplayTitle:
                    workout.title,
                currentPaceSecondsPerKilometer:
                    workout
                        .currentPaceSecondsPerKilometer,
                routeRemainingMeters:
                    workout.routeRemainingMeters,
                routeDeviationMeters:
                    workout.routeDeviationMeters,
                routeDeviationThresholdMeters:
                    workout
                        .routeAlertConfiguration?
                        .deviationMeters,
                runningStepTitle:
                    currentStep?.title,
                runningStepIndex:
                    currentStep == nil
                        ? nil
                        : workout
                            .structuredStepIndex,
                runningStepCount:
                    workout
                        .structuredRunningWorkout?
                        .steps.count,
                runningStepProgress:
                    runningStepProgress,
                runningNextStepTitle:
                    nextStepTitle,
                ghostRaceTitle:
                    workout.ghostRaceTitle,
                ghostDistanceDeltaMeters:
                    workout
                        .ghostDistanceDeltaMeters,
                ghostTimeDeltaSeconds:
                    workout
                        .ghostTimeDeltaSeconds,
                liveSurfaceConfiguration:
                    ATHLTHLiveWorkoutPreferencesStore
                        .load(),
                liveSurfaceContext:
                    ATHLTHLiveWorkoutContextStore
                        .load()
            )

        ATHLTHSurfaceCoordinator
            .syncLiveActivity(
                with: snapshot
            )
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

    private func accept(
        _ locations: [CLLocation]
    ) {
        guard var workout = active else {
            return
        }

        var accepted = false
        var stateChanged = false

        for location in locations {
            guard
                abs(
                    location.timestamp
                        .timeIntervalSinceNow
                ) < 15,
                location.horizontalAccuracy >= 0,
                location.horizontalAccuracy <= 30
            else {
                continue
            }

            if workout.autoPauseEnabled == true {
                if let action =
                        autoPauseDetector.evaluate(
                            location,
                            walking:
                                workout.walking
                        ) {
                    switch action {
                    case .pause:
                        applyAutomaticPause(
                            workout: &workout,
                            at:
                                location.timestamp
                        )
                        stateChanged = true
                        continue

                    case .resume:
                        applyAutomaticResume(
                            workout: &workout,
                            at:
                                location.timestamp
                        )
                        stateChanged = true
                        continue
                    }
                }
            }

            guard let resumedAt =
                    workout.resumedAt,
                  location.timestamp >= resumedAt
            else {
                continue
            }

            if let previous = lastLocation {
                let seconds =
                    location.timestamp
                        .timeIntervalSince(
                            previous.timestamp
                        )

                guard seconds > 0 else {
                    continue
                }

                let distance =
                    location.distance(
                        from: previous
                    )

                // Ignore long signal gaps and implausible jumps rather than
                // inventing distance.
                if seconds <= 30,
                   distance / seconds <= 12 {
                    workout.distanceMeters +=
                        distance
                }
            }

            lastLocation = location
            workout.points.append(
                PhoneRoutePoint(location)
            )
            workout.lastCheckpoint = Date()
            updatePace(
                workout: &workout,
                location: location
            )
            updateRouteGuidance(
                workout: &workout,
                location: location
            )
            accepted = true

            if !automaticPauseActive {
                message = nil
            }
        }

        guard accepted || stateChanged else {
            return
        }

        if accepted {
            evaluateStructuredWorkout(
                &workout
            )
            evaluateCoachAnnouncements(
                workout
            )
        }

        active = workout
        persistActiveCheckpoint(
            force: stateChanged
        )
        syncLiveActivity()
    }

}
