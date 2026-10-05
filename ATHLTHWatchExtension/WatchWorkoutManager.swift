@preconcurrency import AVFoundation
@preconcurrency import CoreLocation
import Foundation
@preconcurrency import HealthKit
@preconcurrency import WatchConnectivity
@preconcurrency import WatchKit

private struct WatchLocationSample: Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let course: Double
    let speed: Double
    let timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        horizontalAccuracy =
            location.horizontalAccuracy
        verticalAccuracy =
            location.verticalAccuracy
        course = location.course
        speed = location.speed
        timestamp = location.timestamp
    }

    func makeLocation() -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            ),
            altitude: altitude,
            horizontalAccuracy:
                horizontalAccuracy,
            verticalAccuracy:
                verticalAccuracy,
            course: course,
            speed: speed,
            timestamp: timestamp
        )
    }
}

private struct WatchPersistedWorkoutState: Codable {
    var kind: WatchWorkoutKind
    var startedAt: Date?
    var plannedRoute: WatchRouteTransfer?
    var audioCoach: WatchAudioCoachConfiguration
    var structuredRunningWorkout: WatchRunningWorkoutTransfer?
    var structuredStepIndex: Int
    var structuredStepStartElapsedTime: TimeInterval
    var structuredStepStartDistanceMeters: Double
    var ghostRace: WatchGhostRaceTransfer?
    var lapSummaries: [WatchWorkoutLapSummary]
    var lapCount: Int
    var lastLapElapsedTime: TimeInterval
    var lastLapDistanceMeters: Double
    var automaticPauseCount: Int
    var automaticPauseEnabled: Bool? = nil
    var strengthSession:
        WatchStrengthSessionSnapshot? = nil
    var strengthCommands:
        [WatchStrengthCommand]? = nil
}

enum WatchWorkoutState: Equatable {
    case idle
    case preparing
    case running
    case paused
    case ending
    case completed
    case failed(String)
}

@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    @MainActor static let shared = WatchWorkoutManager()

    @Published private(set) var state: WatchWorkoutState = .idle
    @Published private(set) var kind: WatchWorkoutKind = .running
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var heartRate: Double = 0
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var currentPaceSecondsPerKilometer:
        TimeInterval?
    @Published private(set) var routeProgressPercent: Double?
    @Published private(set) var routeRemainingMeters: Double?
    @Published private(set) var routeDeviationMeters: Double?
    @Published private(set) var routeDistanceToStartMeters: Double?
    @Published private(set) var routeAlertConfiguration:
        WatchRouteAlertConfiguration = .standard
    @Published private(set) var targetAlertConfiguration:
        WatchWorkoutTargetAlertConfiguration?
    @Published private(set) var liveTargetStatus: String?
    @Published private(set) var ghostRaceTitle: String?
    @Published private(set) var ghostDistanceDeltaMeters: Double?
    @Published private(set) var ghostTimeDeltaSeconds: TimeInterval?
    @Published private(set) var ghostMapUserLatitude: Double?
    @Published private(set) var ghostMapUserLongitude: Double?
    @Published private(set) var ghostMapLatitude: Double?
    @Published private(set) var ghostMapLongitude: Double?
    @Published private(set) var ghostMapRevision = 0
    @Published private(set) var lapCount = 0
    @Published private(set) var currentLapElapsedTime: TimeInterval = 0
    @Published private(set) var currentLapDistanceMeters: Double = 0
    @Published private(set) var lapSummaries: [WatchWorkoutLapSummary] = []
    @Published private(set) var automaticPauseActive = false
    @Published private(set) var automaticPauseEnabled = false
    @Published private(set) var automaticPauseCount = 0
    @Published private(set) var averageHeartRate: Double?
    @Published private(set) var maxHeartRate: Double?
    @Published private(set) var routePoints: [WatchRoutePoint] = []
    @Published private(set) var plannedRoute: WatchRouteTransfer?
    @Published private(set) var audioCoachConfiguration:
        WatchAudioCoachConfiguration = .disabled
    @Published private(set) var structuredRunningWorkout:
        WatchRunningWorkoutTransfer?
    @Published private(set) var treadmillInclinePercent:
        Double?
    @Published private(set) var structuredStepIndex = 0
    @Published private(set) var strengthSession:
        WatchStrengthSessionSnapshot?
    @Published private(set) var strengthActionPending = false
    @Published private(set) var liveSurfaceConfiguration:
        ATHLTHLiveWorkoutSurfaceConfiguration =
            ATHLTHLiveWorkoutPreferencesStore.load()
    @Published private(set) var liveSurfaceContext:
        ATHLTHLiveWorkoutContext = .empty
    @Published private(set) var completedResult: WatchWorkoutResult?
    @Published private(set) var errorMessage: String?

    private let healthStore = HKHealthStore()
    private let locationManager = CLLocationManager()

    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var workoutLocation: CLLocation?
    private var workoutLocationMetadataAttached = false
    private var timer: Timer?
    private var startedAt: Date?
    private var finishing = false
    private var mirroringActive = false
    private var mirroringRetryPending = false
    private var lastMirrorSnapshotSentAt: Date?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var coachAudioSessionIsActive = false
    private var audioCoachActivationTask:
        Task<Void, Never>?
    private var audioCoachReadyAnnouncedForWorkout = false
    private var strengthRestCoachTask:
        Task<Void, Never>?
    private var strengthStatusCoachTask:
        Task<Void, Never>?
    private var guidancePriorityGate =
        ATHLTHGuidancePriorityGate()
    private var nextDistanceAnnouncementMeters: Double?
    private var nextTimeAnnouncementSeconds: TimeInterval?
    private var structuredStepStartElapsedTime: TimeInterval = 0
    private var structuredStepStartDistanceMeters: Double = 0
    private var structuredWorkoutComplete = false
    private var plannedRouteLocations: [CLLocation] = []
    private var plannedRouteCumulativeMeters: [Double] = []
    private var plannedRouteGeometryMeters: Double = 0
    private var ghostRaceConfiguration:
        WatchGhostRaceTransfer?
    private var nextGhostDistanceAnnouncementMeters: Double?
    private var nextGhostTimeAnnouncementSeconds: TimeInterval?
    private var lastGhostAnnouncedLeadMeters: Double?
    private var lastGhostLeadAlertAt: Date?
    private var lastGhostLeadSign = 0
    private var lastGhostMapPublishedAt: Date?
    private var offRouteStartedAt: Date?
    private var lastOffRouteAlertAt: Date?
    private var routeWasOff = false
    private var targetViolationStartedAt: Date?
    private var lastTargetAlertAt: Date?
    private var targetWasOutside = false
    private var lastLapElapsedTime: TimeInterval = 0
    private var lastLapDistanceMeters: Double = 0

    // GPS is a display/result fallback only. HealthKit remains the primary
    // distance source whenever it is delivering fresh workout statistics.
    private var gpsFallbackDistanceMeters: Double = 0
    private var lastAcceptedOutdoorLocation: CLLocation?
    private var healthKitDistanceMeters: Double = 0
    private var healthKitDistanceLastUpdatedAt: Date?
    private var autoPauseDetector =
        OutdoorAutoPauseDetector()
    private var manualPauseActive = false

    private var capturedRouteLocations: [CLLocation] = []
    private var lastRenderedRouteLocation: CLLocation?
    private let recoveryDefaultsKey =
        "athlth.watch.activeWorkoutRecovery.v1"
    private var recoveryInProgress = false
    private var workoutInitiatedLocallyOnWatch = false
    private var strengthCommandJournal:
        [WatchStrengthCommand] = []

    private override init() {
        super.init()
        locationManager.delegate = self
        speechSynthesizer.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3
        locationManager.activityType = .fitness
    }

    func configurePlannedRoute(
        _ route: WatchRouteTransfer?
    ) {
        cachePlannedRouteGeometry(route)

        publish {
            self.plannedRoute = route
            self.routeProgressPercent =
                route == nil ? nil : 0
            self.routeRemainingMeters =
                route.map {
                    max(
                        $0.distanceKilometers * 1_000,
                        0
                    )
                }
            self.routeDeviationMeters = nil
            self.routeDistanceToStartMeters = nil
        }

        persistWorkoutRecoveryState()
    }

    func configureAudioCoach(
        _ configuration: WatchAudioCoachConfiguration
    ) {
        let wasEnabled =
            audioCoachConfiguration.enabled

        publish {
            self.audioCoachConfiguration = configuration
        }
        resetAudioCoachThresholds()
        persistWorkoutRecoveryState()

        if !configuration.enabled {
            audioCoachReadyAnnouncedForWorkout = false
            strengthRestCoachTask?.cancel()
            strengthRestCoachTask = nil
            strengthStatusCoachTask?.cancel()
            strengthStatusCoachTask = nil
            audioCoachActivationTask?.cancel()
            audioCoachActivationTask = nil
            speechSynthesizer.stopSpeaking(at: .immediate)
            deactivateAudioCoachAudioSession()
            return
        }

        if !wasEnabled {
            audioCoachReadyAnnouncedForWorkout = false
        }

        if isActive {
            announceAudioCoachReadyIfNeeded()

            if currentStructuredRunningStep != nil {
                announceCurrentStructuredStep(
                    prefix: "Current"
                )
            }

            if let strengthSession {
                scheduleStrengthRestCoach(
                    strengthSession
                )
                scheduleStrengthStatusCoach()
            }
        }
    }

    func updateAudioCoachDuringWorkout(
        _ configuration: WatchAudioCoachConfiguration
    ) {
        let wasEnabled =
            audioCoachConfiguration.enabled

        publish {
            self.audioCoachConfiguration = configuration
        }

        resetAudioCoachThresholds()
        persistWorkoutRecoveryState()

        if !configuration.enabled {
            audioCoachReadyAnnouncedForWorkout = false
            strengthRestCoachTask?.cancel()
            strengthRestCoachTask = nil
            strengthStatusCoachTask?.cancel()
            strengthStatusCoachTask = nil
            speechSynthesizer.stopSpeaking(at: .immediate)
            deactivateAudioCoachAudioSession()
        } else {
            if !wasEnabled {
                audioCoachReadyAnnouncedForWorkout = false
            }
            announceAudioCoachReadyIfNeeded()
        }
    }

    func configureRunningWorkout(
        _ workout: WatchRunningWorkoutTransfer
    ) {
        publish {
            self.structuredRunningWorkout =
                workout.steps.isEmpty ? nil : workout
            self.treadmillInclinePercent =
                workout.treadmillInclinePercent
            self.structuredStepIndex = 0

            if let routeAlerts = workout.routeAlerts {
                self.routeAlertConfiguration =
                    routeAlerts
            }

            self.targetAlertConfiguration =
                workout.targetAlerts
            self.automaticPauseEnabled =
                workout.autoPauseEnabled ?? false
            self.liveTargetStatus = nil
        }

        autoPauseDetector.reset(
            enabled:
                workout.autoPauseEnabled ?? false
        )
        manualPauseActive = false
        structuredStepStartElapsedTime = elapsedTime
        structuredStepStartDistanceMeters = distanceMeters
        structuredWorkoutComplete = false
        offRouteStartedAt = nil
        lastOffRouteAlertAt = nil
        routeWasOff = false
        targetViolationStartedAt = nil
        lastTargetAlertAt = nil
        targetWasOutside = false
        persistWorkoutRecoveryState()

        if isActive,
           !workout.steps.isEmpty {
            announceCurrentStructuredStep(prefix: "Starting")
        }
    }

    func configureGhostRace(
        _ ghost: WatchGhostRaceTransfer?
    ) {
        ghostRaceConfiguration = ghost
        resetGhostAnnouncementThresholds(
            audio: ghost?.audio
        )

        publish {
            self.ghostRaceTitle = ghost?.title
            self.ghostDistanceDeltaMeters = nil
            self.ghostTimeDeltaSeconds = nil
        }

        persistWorkoutRecoveryState()
    }

    private func resetGhostAnnouncementThresholds(
        audio:
            WatchGhostRaceAudioConfiguration?
    ) {
        lastGhostAnnouncedLeadMeters = nil
        lastGhostLeadAlertAt = nil
        lastGhostLeadSign = 0
        lastGhostMapPublishedAt = nil

        if let interval =
                audio?.distanceIntervalMeters,
           interval > 0 {
            nextGhostDistanceAnnouncementMeters =
                (
                    floor(
                        max(distanceMeters, 0) /
                        interval
                    ) + 1
                ) * interval
        } else {
            nextGhostDistanceAnnouncementMeters =
                nil
        }

        if let interval =
                audio?.timeIntervalSeconds,
           interval > 0 {
            nextGhostTimeAnnouncementSeconds =
                (
                    floor(
                        max(elapsedTime, 0) /
                        interval
                    ) + 1
                ) * interval
        } else {
            nextGhostTimeAnnouncementSeconds =
                nil
        }
    }

    private func ghostAudioConfiguration(
        from context:
            ATHLTHLiveGhostAudioContext?
    ) -> WatchGhostRaceAudioConfiguration? {
        guard let context else {
            return nil
        }

        let periodic =
            WatchAlertDelivery(
                rawValue:
                    context
                        .periodicDeliveryRawValue
            ) ?? .voice
        let lead =
            WatchAlertDelivery(
                rawValue:
                    context
                        .leadChangeDeliveryRawValue
            ) ?? .haptic
        let important =
            WatchAlertDelivery(
                rawValue:
                    context
                        .importantLeadChangeDeliveryRawValue
            ) ?? .both

        return WatchGhostRaceAudioConfiguration(
            enabled: context.enabled,
            distanceIntervalMeters:
                context
                    .distanceIntervalMeters,
            timeIntervalSeconds:
                context
                    .timeIntervalSeconds,
            announceLeadChanges:
                context
                    .announceLeadChanges,
            leadChangeThresholdMeters:
                context
                    .leadChangeThresholdMeters,
            delivery: periodic,
            periodicDelivery: periodic,
            leadChangeDelivery: lead,
            importantLeadChangeDelivery:
                important,
            importantLeadChangeMeters:
                context
                    .importantLeadChangeMeters
        )
    }

    var averagePaceSecondsPerKilometer: TimeInterval? {
        guard distanceMeters >= 100,
              elapsedTime > 0
        else {
            return nil
        }

        return elapsedTime /
            (distanceMeters / 1_000)
    }

    var currentStructuredStepElapsedTime: TimeInterval {
        max(
            elapsedTime -
            structuredStepStartElapsedTime,
            0
        )
    }

    var currentStructuredStepDistanceMeters: Double {
        max(
            distanceMeters -
            structuredStepStartDistanceMeters,
            0
        )
    }

    var nextStructuredRunningStep: WatchRunningWorkoutStep? {
        guard let workout = structuredRunningWorkout else {
            return nil
        }

        let index = structuredStepIndex + 1
        return workout.steps.indices.contains(index)
            ? workout.steps[index]
            : nil
    }

    var audioCoachConfigured: Bool {
        let configuration = audioCoachConfiguration

        return configuration.enabled ||
            configuration.distanceIntervalMeters != nil ||
            configuration.timeIntervalSeconds != nil ||
            configuration.announceDistance ||
            configuration.announceElapsedTime ||
            configuration.announceAveragePace ||
            configuration.announceClockTime ||
            configuration.announceHeartRate ||
            configuration.announceRemainingRouteDistance ||
            configuration.announceEstimatedRemainingRouteTime ||
            configuration.announceCurrentWorkoutStep ||
            configuration.announceRemainingStepTime ||
            configuration.announceRemainingStepDistance
    }

    func setAudioCoachEnabled(_ enabled: Bool) {
        guard audioCoachConfigured else {
            return
        }

        publish {
            self.audioCoachConfiguration.enabled = enabled
        }

        resetAudioCoachThresholds()

        persistWorkoutRecoveryState()

        if enabled {
            audioCoachReadyAnnouncedForWorkout = false
            announceAudioCoachReadyIfNeeded()

            if currentStructuredRunningStep != nil {
                announceCurrentStructuredStep(
                    prefix: "Current"
                )
            }
        } else {
            audioCoachReadyAnnouncedForWorkout = false
            audioCoachActivationTask?.cancel()
            audioCoachActivationTask = nil
            speechSynthesizer.stopSpeaking(at: .immediate)
            deactivateAudioCoachAudioSession()
        }
    }

    func markLap() {
        guard kind == .running || kind == .walking,
              state == .running
        else {
            return
        }

        let lapNumber = lapCount + 1
        let lapElapsed =
            max(
                elapsedTime -
                    lastLapElapsedTime,
                0
            )
        let lapDistance =
            max(
                distanceMeters -
                    lastLapDistanceMeters,
                0
            )
        let averagePace:
            TimeInterval? =
            lapDistance >= 25 &&
            lapElapsed > 0
                ? lapElapsed /
                    (lapDistance / 1_000)
                : nil
        let now = Date()

        lapSummaries.append(
            WatchWorkoutLapSummary(
                number: lapNumber,
                endedAt: now,
                elapsedTime: lapElapsed,
                distanceMeters: lapDistance,
                averagePaceSecondsPerKilometer:
                    averagePace
            )
        )

        lapCount = lapNumber
        lastLapElapsedTime = elapsedTime
        lastLapDistanceMeters = distanceMeters
        currentLapElapsedTime = 0
        currentLapDistanceMeters = 0

        if let builder = workoutBuilder {
            let lapStart =
                min(
                    lapSummaries
                        .dropLast()
                        .last?
                        .endedAt ??
                    startedAt ??
                    now,
                    now
                )
            let event =
                HKWorkoutEvent(
                    type: .lap,
                    dateInterval:
                        DateInterval(
                            start: lapStart,
                            end: now
                        ),
                    metadata: [
                        "ATHLTHLapNumber":
                            lapNumber
                    ]
                )

            Task {
                do {
                    try await builder
                        .addWorkoutEvents(
                            [event]
                        )
                } catch {
                    await MainActor.run {
                        self.errorMessage =
                            "Lap was recorded in ATHLTH, but Apple Health couldn't attach the lap event: \(error.localizedDescription)"
                    }
                }
            }
        }

        persistWorkoutRecoveryState()
        WKInterfaceDevice.current().play(.click)
    }

    func configureStrengthSession(
        _ snapshot: WatchStrengthSessionSnapshot
    ) {
        let previous = strengthSession

        if let previous,
           previous.workoutID ==
                snapshot.workoutID {
            // Never let a delayed applicationContext/userInfo payload roll
            // completed strength work backwards. Draft-only changes get a
            // small clock-skew tolerance because iPhone and Watch timestamps
            // come from different devices.
            if snapshot.completedSets <
                previous.completedSets {
                return
            }

            if previous.allExercisesComplete &&
                !snapshot.allExercisesComplete {
                return
            }

            if snapshot.completedSets ==
                    previous.completedSets,
               snapshot.updatedAt
                    .addingTimeInterval(0.75) <
                    previous.updatedAt {
                return
            }
        }

        publish {
            self.strengthSession = snapshot
            self.strengthActionPending = false
        }

        handleStrengthCoachTransition(
            from: previous,
            to: snapshot
        )
        persistWorkoutRecoveryState()
    }

    private func handleStrengthCoachTransition(
        from previous:
            WatchStrengthSessionSnapshot?,
        to current:
            WatchStrengthSessionSnapshot
    ) {
        guard audioCoachConfiguration.enabled
        else {
            strengthRestCoachTask?.cancel()
            strengthStatusCoachTask?.cancel()
            strengthStatusCoachTask = nil
            return
        }

        if let previous,
           current.completedSets >
            previous.completedSets,
           audioCoachConfiguration
            .shouldAnnounceStrengthSetComplete {
            let setNumber =
                previous.setNumber ??
                current.setNumber ??
                current.completedSets

            let weight =
                previous
                    .draftWeightKilograms
            let reps =
                previous.draftReps
            let formattedWeight =
                weight.rounded() == weight
                    ? String(Int(weight))
                    : String(
                        format: "%.1f",
                        weight
                    )

            speak(
                coachPhrase(
                    english:
                        "Set \(setNumber) complete. \(reps) reps at \(formattedWeight) kilograms.",
                    norwegian:
                        "Sett \(setNumber) fullført. \(reps) repetisjoner på \(formattedWeight) kilo."
                )
            )

        }

        if let previous,
           current.exerciseIndex !=
            previous.exerciseIndex,
           audioCoachConfiguration
            .shouldAnnounceStrengthNextExercise,
           let exerciseName =
            current.exerciseName {
            speak(
                coachPhrase(
                    english:
                        "Next exercise. \(exerciseName).",
                    norwegian:
                        "Neste øvelse. \(exerciseName)."
                )
            )
        }

        if previous?.restEndsAt !=
            current.restEndsAt {
            scheduleStrengthRestCoach(
                current
            )
        }

        scheduleStrengthStatusCoach()
    }

    private func scheduleStrengthRestCoach(
        _ snapshot:
            WatchStrengthSessionSnapshot
    ) {
        strengthRestCoachTask?.cancel()
        strengthRestCoachTask = nil

        guard audioCoachConfiguration.enabled,
              snapshot.isResting,
              let restEndsAt =
                snapshot.restEndsAt
        else {
            return
        }

        let countdownSeconds =
            audioCoachConfiguration
                .resolvedStrengthRestCountdownSeconds
        let remaining =
            max(
                Int(
                    restEndsAt
                        .timeIntervalSinceNow
                        .rounded()
                ),
                0
            )

        if audioCoachConfiguration
            .shouldAnnounceStrengthRestStarted {
            speak(
                coachPhrase(
                    english:
                        "Rest started. \(remaining) seconds.",
                    norwegian:
                        "Hvile startet. \(remaining) sekunder."
                )
            )
        }

        strengthRestCoachTask =
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                let countdownDelay =
                    restEndsAt
                        .timeIntervalSinceNow -
                    TimeInterval(
                        countdownSeconds
                    )

                if countdownDelay > 0 {
                    try? await Task.sleep(
                        for:
                            .seconds(
                                countdownDelay
                            )
                    )
                }

                guard !Task.isCancelled,
                      self.strengthSession?
                        .restEndsAt ==
                        restEndsAt
                else {
                    return
                }

                if self.audioCoachConfiguration
                    .shouldUseStrengthHaptics {
                    WKInterfaceDevice.current()
                        .play(.click)
                }

                if self.audioCoachConfiguration
                    .shouldAnnounceStrengthRestCountdown {
                    self.speak(
                        self.coachPhrase(
                            english:
                                "\(countdownSeconds) seconds left.",
                            norwegian:
                                "\(countdownSeconds) sekunder igjen."
                        )
                    )
                }

                let finalDelay =
                    restEndsAt
                        .timeIntervalSinceNow

                if finalDelay > 0 {
                    try? await Task.sleep(
                        for:
                            .seconds(
                                finalDelay
                            )
                    )
                }

                guard !Task.isCancelled,
                      self.strengthSession?
                        .restEndsAt ==
                        restEndsAt
                else {
                    return
                }

                if self.audioCoachConfiguration
                    .shouldUseStrengthHaptics {
                    WKInterfaceDevice.current()
                        .play(.success)
                }

                if self.audioCoachConfiguration
                    .shouldAnnounceStrengthRestComplete {
                    self.speak(
                        self.coachPhrase(
                            english:
                                "Rest complete. Ready for the next set.",
                            norwegian:
                                "Hvilen er ferdig. Klar for neste sett."
                        )
                    )
                }
            }
    }

    private func scheduleStrengthStatusCoach() {
        guard strengthStatusCoachTask == nil,
              audioCoachConfiguration.enabled,
              let interval =
                audioCoachConfiguration
                    .strengthStatusIntervalSeconds,
              interval > 0
        else {
            return
        }

        strengthStatusCoachTask =
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                while !Task.isCancelled {
                    try? await Task.sleep(
                        for:
                            .seconds(
                                max(
                                    interval,
                                    300
                                )
                            )
                    )

                    guard !Task.isCancelled,
                          self.kind == .strength,
                          let snapshot =
                            self.strengthSession
                    else {
                        return
                    }

                    let exercise =
                        snapshot.exerciseName ??
                        snapshot.title

                    self.speak(
                        self.coachPhrase(
                            english:
                                "\(snapshot.completedSets) sets complete. Current exercise: \(exercise).",
                            norwegian:
                                "\(snapshot.completedSets) sett fullført. Nåværende øvelse: \(exercise)."
                        )
                    )
                }
            }
    }

    func configureLiveSurface(
        _ configuration: ATHLTHLiveWorkoutSurfaceConfiguration
    ) {
        ATHLTHLiveWorkoutPreferencesStore.save(configuration)

        publish {
            self.liveSurfaceConfiguration = configuration
        }
    }

    func configureLiveSurfaceContext(
        _ context: ATHLTHLiveWorkoutContext
    ) {
        let previousLiveGhostTitle =
            liveSurfaceContext
                .liveGhost?
                .title

        publish {
            self.liveSurfaceContext = context
        }

        // A fixed Replay/Target Ghost owns its own comparison stream.
        guard ghostRaceConfiguration == nil
        else {
            return
        }

        guard let liveGhost =
                    context.liveGhost
        else {
            resetGhostAnnouncementThresholds(
                audio: nil
            )
            publish {
                self.ghostRaceTitle = nil
                self.ghostDistanceDeltaMeters =
                    nil
                self.ghostTimeDeltaSeconds =
                    nil
            }
            return
        }

        if previousLiveGhostTitle !=
            liveGhost.title {
            resetGhostAnnouncementThresholds(
                audio:
                    ghostAudioConfiguration(
                        from: liveGhost.audio
                    )
            )
        }

        publish {
            self.ghostRaceTitle =
                liveGhost.title
            self.ghostDistanceDeltaMeters =
                liveGhost.distanceDeltaMeters
            self.ghostTimeDeltaSeconds =
                liveGhost
                    .estimatedTimeDeltaSeconds
        }

        guard isActive,
              kind == .running,
              let distanceDelta =
                    liveGhost
                        .distanceDeltaMeters
        else {
            return
        }

        evaluateGhostRaceCoach(
            configuration:
                ghostAudioConfiguration(
                    from: liveGhost.audio
                ),
            userDistance:
                distanceMeters,
            distanceDelta:
                distanceDelta,
            timeDelta:
                liveGhost
                    .estimatedTimeDeltaSeconds
        )
    }

    func updateStrengthDraft(
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        weightKilograms: Double? = nil,
        resistanceLevel: Int? = nil,
        restSeconds: Int? = nil,
        rpe: Double? = nil,
        rir: Double? = nil,
        isWarmUp: Bool? = nil
    ) {
        guard var snapshot = strengthSession else {
            requestStrengthSnapshot()
            return
        }

        if let reps {
            snapshot.draftReps = max(reps, 0)
        }
        if let durationSeconds {
            snapshot.draftDurationSeconds =
                min(max(durationSeconds, 0), 7_200)
        }
        if let weightKilograms {
            snapshot.draftWeightKilograms =
                max(weightKilograms, 0)
        }
        if let resistanceLevel {
            snapshot.draftResistanceLevel =
                min(max(resistanceLevel, 1), 10)
        }
        if let restSeconds {
            snapshot.draftRestSeconds =
                min(max(restSeconds, 0), 600)
        }
        if let rpe {
            snapshot.draftRPE =
                min(max(rpe, 1), 10)
        }
        if let rir {
            snapshot.draftRIR =
                min(max(rir, 0), 10)
        }
        if let isWarmUp {
            snapshot.isWarmUp =
                isWarmUp
        }
        snapshot.updatedAt = Date()

        publish {
            self.strengthSession = snapshot
        }

        sendStrengthCommand(
            WatchStrengthCommand(
                id: UUID(),
                workoutID: snapshot.workoutID,
                kind: .updateDraft,
                reps: snapshot.draftReps,
                weightKilograms:
                    snapshot.draftWeightKilograms,
                restSeconds:
                    snapshot.draftRestSeconds,
                durationSeconds:
                    snapshot.draftDurationSeconds,
                resistanceLevel:
                    snapshot.draftResistanceLevel,
                addRestSeconds: nil,
                sentAt: Date(),
                rpe: snapshot.draftRPE,
                rir: snapshot.draftRIR,
                isWarmUp:
                    snapshot.isWarmUp,
                exerciseIndex:
                    snapshot.exerciseIndex,
                setIndex:
                    snapshot.setIndex
            )
        )
    }

    func completeStrengthSet() {
        guard !strengthActionPending,
              let snapshot =
                strengthSession
        else {
            return
        }

        let sent =
            sendStrengthCommand(
                WatchStrengthCommand(
                    id: UUID(),
                    workoutID:
                        snapshot.workoutID,
                    kind: .completeSet,
                    reps:
                        snapshot.draftReps,
                    weightKilograms:
                        snapshot
                            .draftWeightKilograms,
                    restSeconds:
                        snapshot
                            .draftRestSeconds,
                    durationSeconds:
                        snapshot
                            .draftDurationSeconds,
                    resistanceLevel:
                        snapshot
                            .draftResistanceLevel,
                    addRestSeconds: nil,
                    sentAt: Date(),
                    rpe:
                        snapshot.draftRPE,
                    rir:
                        snapshot.draftRIR,
                    isWarmUp:
                        snapshot.isWarmUp,
                    exerciseIndex:
                        snapshot.exerciseIndex,
                    setIndex:
                        snapshot.setIndex
                )
            )

        if sent {
            // Watch is the local source of truth for interaction. Advance
            // immediately even when iPhone is reachable; the returned iPhone
            // snapshot can only confirm/equal this state and cannot roll it
            // backwards.
            applyOptimisticStrengthCompletion(
                snapshot
            )
        }
    }

    func skipStrengthRest() {
        guard let snapshot = strengthSession else {
            return
        }

        let shouldAdvanceExercise =
            snapshot.currentExerciseComplete &&
            snapshot.hasNextExercise

        let sent =
            sendStrengthCommand(
                WatchStrengthCommand(
                    id: UUID(),
                    workoutID: snapshot.workoutID,
                    kind: .skipRest,
                    reps: nil,
                    weightKilograms: nil,
                    restSeconds: nil,
                    addRestSeconds: nil,
                    sentAt: Date()
                )
            )

        if sent {
            publish {
                var updated = snapshot
                updated.isResting = false
                updated.restEndsAt = nil
                updated.updatedAt = Date()
                self.strengthSession = updated
            }
            persistWorkoutRecoveryState()

            if shouldAdvanceExercise {
                moveToNextStrengthExercise()
            }
        }
    }

    func addStrengthRest(seconds: Int = 30) {
        guard let snapshot = strengthSession else {
            return
        }

        let addedSeconds =
            max(seconds, 0)
        let sent =
            sendStrengthCommand(
                WatchStrengthCommand(
                    id: UUID(),
                    workoutID: snapshot.workoutID,
                    kind: .addRest,
                    reps: nil,
                    weightKilograms: nil,
                    restSeconds: nil,
                    addRestSeconds:
                        addedSeconds,
                    sentAt: Date()
                )
            )

        if sent {
            publish {
                var updated = snapshot
                let base =
                    max(
                        updated.restEndsAt ??
                            Date(),
                        Date()
                    )
                updated.isResting =
                    addedSeconds > 0
                updated.restEndsAt =
                    addedSeconds > 0
                        ? base
                            .addingTimeInterval(
                                TimeInterval(
                                    addedSeconds
                                )
                            )
                        : nil
                updated.updatedAt = Date()
                self.strengthSession = updated
            }
            persistWorkoutRecoveryState()
        }
    }

    func moveToNextStrengthExercise() {
        guard !strengthActionPending,
              let snapshot =
                strengthSession
        else {
            return
        }

        let sent =
            sendStrengthCommand(
                WatchStrengthCommand(
                    id: UUID(),
                    workoutID:
                        snapshot.workoutID,
                    kind: .nextExercise,
                    reps: nil,
                    weightKilograms: nil,
                    restSeconds: nil,
                    addRestSeconds: nil,
                    sentAt: Date(),
                    exerciseIndex:
                        snapshot.exerciseIndex,
                    setIndex:
                        snapshot.setIndex
                )
            )

        if sent {
            applyOptimisticNextStrengthExercise(
                snapshot
            )
        }
    }

    private var strengthCompanionReachable:
        Bool {
        WCSession.isSupported() &&
        WCSession.default.activationState ==
            .activated &&
        WCSession.default.isReachable
    }

    private func applyOptimisticStrengthCompletion(
        _ snapshot:
            WatchStrengthSessionSnapshot
    ) {
        var updated = snapshot
        updated.completedSets =
            min(
                snapshot.completedSets + 1,
                snapshot.totalSets
            )

        let nextSetIndex =
            snapshot.setIndex + 1

        if nextSetIndex <
            snapshot.setCount {
            updated.setIndex =
                nextSetIndex
            updated.setNumber =
                nextSetIndex + 1
            updated.currentExerciseComplete =
                false
            updated.allExercisesComplete =
                false
            applyStrengthPlanDefaults(
                to: &updated,
                exerciseIndex:
                    snapshot.exerciseIndex,
                setIndex:
                    nextSetIndex
            )
        } else {
            updated.currentExerciseComplete =
                true
            updated.setNumber =
                snapshot.setCount
            updated.allExercisesComplete =
                updated.completedSets >=
                    updated.totalSets
        }

        if snapshot.draftRestSeconds > 0 &&
            !updated.allExercisesComplete {
            updated.isResting = true
            updated.restEndsAt =
                Date()
                    .addingTimeInterval(
                        TimeInterval(
                            snapshot
                                .draftRestSeconds
                        )
                    )
        } else {
            updated.isResting = false
            updated.restEndsAt = nil
        }

        updated.updatedAt = Date()

        publish {
            self.strengthSession = updated
            self.strengthActionPending =
                false
        }
        persistWorkoutRecoveryState()
    }

    private func applyOptimisticNextStrengthExercise(
        _ snapshot:
            WatchStrengthSessionSnapshot
    ) {
        guard let queue =
                snapshot.exerciseQueue,
              let next =
                queue
                    .first(
                        where: {
                            $0.index >
                            snapshot.exerciseIndex
                        }
                    )
        else {
            publish {
                self.strengthActionPending =
                    false
            }
            return
        }

        var updated = snapshot
        updated.exerciseIndex =
            next.index
        updated.exerciseName =
            next.name
        updated.primaryMuscles =
            next.primaryMuscles
        updated.setIndex = 0
        updated.setCount =
            next.setCount
        updated.setNumber =
            next.setCount > 0
                ? 1
                : nil
        updated.currentExerciseComplete =
            next.setCount == 0
        updated.hasNextExercise =
            queue.contains {
                $0.index >
                next.index
            }
        updated.allExercisesComplete =
            false
        applyStrengthPlanDefaults(
            to: &updated,
            exerciseIndex:
                next.index,
            setIndex: 0
        )
        updated.isResting = false
        updated.restEndsAt = nil
        updated.updatedAt = Date()

        publish {
            self.strengthSession = updated
            self.strengthActionPending =
                false
        }
        persistWorkoutRecoveryState()
    }

    func requestStrengthSnapshot() {
        sendStrengthCommand(
            WatchStrengthCommand(
                id: UUID(),
                workoutID: strengthSession?.workoutID,
                kind: .requestSnapshot,
                reps: nil,
                weightKilograms: nil,
                restSeconds: nil,
                addRestSeconds: nil,
                sentAt: Date(),
                initiatedOnWatch:
                    workoutInitiatedLocallyOnWatch,
                bootstrapSnapshot:
                    workoutInitiatedLocallyOnWatch
                        ? strengthSession
                        : nil
            )
        )
    }

    @discardableResult
    private func sendStrengthCommand(
        _ rawCommand: WatchStrengthCommand
    ) -> Bool {
        var command = rawCommand
        if command.kind == .requestSnapshot,
           command.bootstrapSnapshot == nil,
           workoutInitiatedLocallyOnWatch {
            command.bootstrapSnapshot =
                strengthSession
        }

        if !strengthCommandJournal
            .contains(where: {
                $0.id == command.id
            }) {
            strengthCommandJournal.append(
                command
            )
            if strengthCommandJournal.count >
                512 {
                strengthCommandJournal =
                    Array(
                        strengthCommandJournal
                            .suffix(384)
                    )
            }
        }

        guard let data =
                try? JSONEncoder()
                    .encode(command)
        else {
            return false
        }

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind:
                WatchTransferKind
                    .strengthCommand
                    .rawValue,
            WatchTransferMetadataKey.payload:
                data,
            WatchTransferMetadataKey.sentAt:
                command.sentAt
                    .timeIntervalSince1970
        ]

        if WCSession.isSupported(),
           WCSession.default.activationState ==
                .activated {
            // Always queue a durable copy. sendMessage remains the low-latency
            // fast path, while transferUserInfo guarantees replay after hours
            // away from iPhone or the internet.
            WCSession.default.transferUserInfo(
                payload
            )

            if WCSession.default.isReachable {
                WCSession.default.sendMessage(
                    payload,
                    replyHandler: nil,
                    errorHandler: nil
                )
            }
        }

        // No companion session is required for local Watch logging. The full
        // journal is also embedded in WatchWorkoutResult at finish.
        persistWorkoutRecoveryState()
        return true
    }

    nonisolated private static func makeStrengthCommandFallbackHandler(
        payload: [String: Any]
    ) -> (Error) -> Void {
        { _ in
            WCSession.default
                .transferUserInfo(payload)
        }
    }

    private func ensureStandaloneStrengthSession(
        title: String =
            ATHLTHLocalization.choose(
                english: "Freestyle Strength",
                norwegian: "Fri styrke"
            )
    ) {
        guard strengthSession == nil else {
            return
        }

        let workoutID = UUID()
        let setPlans =
            (1...3).map {
                WatchStrengthSetPlan(
                    setNumber: $0,
                    reps: 8,
                    weightKilograms: 20,
                    restSeconds: 90,
                    isWarmUp: nil
                )
            }

        let exercise =
            WatchStrengthExerciseSummary(
                index: 0,
                name:
                    ATHLTHLocalization.choose(
                        english: "Strength",
                        norwegian: "Styrke"
                    ),
                primaryMuscles: [],
                setCount: setPlans.count,
                instructions: [],
                secondaryMuscles: [],
                equipment: [],
                setPlans: setPlans
            )

        let snapshot =
            WatchStrengthSessionSnapshot(
                workoutID: workoutID,
                title: title,
                exerciseIndex: 0,
                exerciseCount: 1,
                exerciseName:
                    exercise.name,
                primaryMuscles: [],
                setIndex: 0,
                setCount:
                    exercise.setCount,
                setNumber: 1,
                completedSets: 0,
                totalSets:
                    exercise.setCount,
                draftReps: 8,
                draftWeightKilograms: 20,
                draftRestSeconds: 90,
                draftDurationSeconds: nil,
                draftResistanceLevel: nil,
                targetKindRaw: "reps",
                loadKindRaw:
                    "weightKilograms",
                isResting: false,
                restEndsAt: nil,
                currentExerciseComplete:
                    false,
                hasNextExercise: false,
                allExercisesComplete: false,
                updatedAt: Date(),
                inputMode: .appleWatch,
                draftRPE: 8,
                draftRIR: 2,
                isWarmUp: false,
                effortMetricRaw: "rpe",
                exerciseQueue: [exercise],
                startedAt: Date(),
                plannedSessionID: nil,
                allowsLiveExerciseBuilding:
                    true
            )

        strengthCommandJournal = []
        publish {
            self.strengthSession =
                snapshot
            self.strengthActionPending =
                false
        }
        persistWorkoutRecoveryState()
    }

    private func markStandaloneStrengthStarted() {
        guard var snapshot =
                strengthSession
        else {
            return
        }

        let now = Date()
        snapshot.startedAt = now
        snapshot.updatedAt = now
        snapshot.inputMode =
            .appleWatch
        snapshot.isResting = false
        snapshot.restEndsAt = nil
        snapshot.completedSets = 0
        snapshot.allExercisesComplete =
            false
        snapshot.currentExerciseComplete =
            false
        snapshot.exerciseIndex = 0
        snapshot.setIndex = 0
        snapshot.setNumber =
            snapshot.setCount > 0
                ? 1
                : nil

        if let first =
                snapshot.exerciseQueue?
                    .sorted(by: {
                        $0.index < $1.index
                    })
                    .first {
            snapshot.exerciseName =
                first.name
            snapshot.primaryMuscles =
                first.primaryMuscles
            snapshot.setCount =
                first.setCount
            snapshot.hasNextExercise =
                (snapshot.exerciseQueue?.count ??
                    0) > 1
            applyStrengthPlanDefaults(
                to: &snapshot,
                exerciseIndex:
                    first.index,
                setIndex: 0
            )
        }

        strengthCommandJournal = []
        publish {
            self.strengthSession =
                snapshot
            self.strengthActionPending =
                false
        }
        persistWorkoutRecoveryState()
    }

    private func applyStrengthPlanDefaults(
        to snapshot:
            inout WatchStrengthSessionSnapshot,
        exerciseIndex: Int,
        setIndex: Int
    ) {
        guard let exercise =
                snapshot.exerciseQueue?
                    .first(
                        where: {
                            $0.index ==
                                exerciseIndex
                        }
                    ),
              let plans =
                exercise.setPlans,
              plans.indices.contains(setIndex)
        else {
            return
        }

        let plan = plans[setIndex]

        if let reps = plan.reps {
            snapshot.draftReps =
                max(reps, 0)
            snapshot
                .targetKindRaw =
                "reps"
        }

        if let duration =
                plan.durationSeconds {
            snapshot.draftDurationSeconds =
                max(duration, 0)
            snapshot
                .targetKindRaw =
                "time"
        } else {
            snapshot.draftDurationSeconds =
                nil
        }

        if let weight =
                plan.weightKilograms {
            snapshot.draftWeightKilograms =
                max(weight, 0)
            snapshot.loadKindRaw =
                "weightKilograms"
        }

        if let resistance =
                plan.resistanceLevel {
            snapshot.draftResistanceLevel =
                min(max(resistance, 1), 10)
            snapshot.loadKindRaw =
                "resistanceLevel"
        } else {
            snapshot.draftResistanceLevel =
                nil
        }

        if let rest =
                plan.restSeconds {
            snapshot.draftRestSeconds =
                min(max(rest, 0), 600)
        }

        snapshot.isWarmUp =
            plan.isWarmUp
    }

    var currentStructuredRunningStep: WatchRunningWorkoutStep? {
        guard let structuredRunningWorkout,
              structuredRunningWorkout.steps.indices.contains(
                structuredStepIndex
              )
        else {
            return nil
        }

        return structuredRunningWorkout.steps[structuredStepIndex]
    }

    var isWorkoutPresented: Bool {
        switch state {
        case .idle, .failed:
            return false
        case .preparing, .running, .paused, .ending, .completed:
            return true
        }
    }

    var isActive: Bool {
        state == .running || state == .paused
    }

    func recoverActiveWorkout() async {
        guard workoutSession == nil,
              !recoveryInProgress
        else {
            return
        }

        recoveryInProgress = true
        defer {
            recoveryInProgress = false
        workoutInitiatedLocallyOnWatch = false
        }

        do {
            guard let recovered =
                    try await healthStore
                        .recoverActiveWorkoutSession()
            else {
                clearPersistedWorkoutState()
                return
            }

            let configuration =
                recovered.workoutConfiguration
            let recoveredKind =
                kind(
                    for:
                        configuration
                            .activityType
                )
            let builder =
                recovered
                    .associatedWorkoutBuilder()

            recovered.delegate = self
            builder.delegate = self
            builder.dataSource =
                HKLiveWorkoutDataSource(
                    healthStore: healthStore,
                    workoutConfiguration:
                        configuration
                )

            workoutSession = recovered
            workoutBuilder = builder
            finishing = false
            kind = recoveredKind
            startedAt =
                recovered.startDate ??
                builder.startDate ??
                Date()

            restorePersistedWorkoutState(
                expectedKind: recoveredKind
            )

            if configuration.locationType ==
                .outdoor,
               let seriesBuilder =
                    builder.seriesBuilder(
                        for:
                            HKSeriesType
                                .workoutRoute()
                    ) as? HKWorkoutRouteBuilder {
                routeBuilder = seriesBuilder
                locationManager
                    .requestWhenInUseAuthorization()
                locationManager
                    .allowsBackgroundLocationUpdates =
                    true
                locationManager
                    .startUpdatingLocation()
            } else {
                routeBuilder = nil
            }

            updateFinalStatistics(
                from: builder
            )
            elapsedTime =
                builder.elapsedTime

            switch recovered.state {
            case .running:
                publishState(.running)
            case .paused:
                publishState(.paused)
            case .stopped, .ended:
                publishState(.ending)
            default:
                publishState(.preparing)
            }

            if recovered.state == .running ||
                recovered.state == .paused {
                startTimer()
            }

            persistWorkoutRecoveryState()

            if recovered.state == .running ||
                recovered.state == .paused {
                do {
                    try await recovered
                        .startMirroringToCompanionDevice()
                    mirroringActive = true
                    mirroringRetryPending = false
                } catch {
                    mirroringActive = false
                    mirroringRetryPending = true
                }

                await sendLiveSnapshot(
                    stateOverride:
                        recovered.state == .paused
                            ? .paused
                            : .running,
                    force: true
                )
                WatchHomeAssistantBridge.shared
                    .workoutStarted(
                        kind: kind,
                        startedAt: startedAt
                    )
            }
        } catch {
            fail(
                message:
                    "ATHLTH couldn't recover the active workout: \(error.localizedDescription)"
            )
        }
    }

    func startPreparedWorkout(
        kind: WatchWorkoutKind,
        route: WatchRouteTransfer? = nil
    ) async {
        workoutInitiatedLocallyOnWatch = true

        if kind == .strength {
            ensureStandaloneStrengthSession()
            markStandaloneStrengthStarted()
        }

        let configuration =
            HKWorkoutConfiguration()
        configuration.activityType =
            activityType(for: kind)
        configuration.locationType =
            kind.usesOutdoorLocation
                ? .outdoor
                : .indoor

        await start(
            configuration: configuration,
            kind: kind,
            route: route
        )
    }

    private func persistWorkoutRecoveryState() {
        guard state != .idle,
              state != .completed
        else {
            return
        }

        let snapshot =
            WatchPersistedWorkoutState(
                kind: kind,
                startedAt: startedAt,
                plannedRoute: plannedRoute,
                audioCoach:
                    audioCoachConfiguration,
                structuredRunningWorkout:
                    structuredRunningWorkout,
                structuredStepIndex:
                    structuredStepIndex,
                structuredStepStartElapsedTime:
                    structuredStepStartElapsedTime,
                structuredStepStartDistanceMeters:
                    structuredStepStartDistanceMeters,
                ghostRace:
                    ghostRaceConfiguration,
                lapSummaries:
                    lapSummaries,
                lapCount: lapCount,
                lastLapElapsedTime:
                    lastLapElapsedTime,
                lastLapDistanceMeters:
                    lastLapDistanceMeters,
                automaticPauseCount:
                    automaticPauseCount,
                automaticPauseEnabled:
                    automaticPauseEnabled,
                strengthSession:
                    strengthSession,
                strengthCommands:
                    strengthCommandJournal
            )

        guard let data =
                try? JSONEncoder()
                    .encode(snapshot)
        else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: recoveryDefaultsKey
        )
    }

    private func restorePersistedWorkoutState(
        expectedKind: WatchWorkoutKind
    ) {
        guard let data =
                UserDefaults.standard.data(
                    forKey:
                        recoveryDefaultsKey
                ),
              let snapshot =
                try? JSONDecoder().decode(
                    WatchPersistedWorkoutState.self,
                    from: data
                ),
              snapshot.kind == expectedKind
        else {
            return
        }

        startedAt =
            startedAt ??
            snapshot.startedAt
        ghostRaceConfiguration =
            snapshot.ghostRace
        strengthCommandJournal =
            snapshot.strengthCommands ?? []
        structuredStepStartElapsedTime =
            snapshot
                .structuredStepStartElapsedTime
        structuredStepStartDistanceMeters =
            snapshot
                .structuredStepStartDistanceMeters
        lastLapElapsedTime =
            snapshot.lastLapElapsedTime
        lastLapDistanceMeters =
            snapshot.lastLapDistanceMeters

        cachePlannedRouteGeometry(
            snapshot.plannedRoute
        )

        publish {
            self.plannedRoute =
                snapshot.plannedRoute
            self.audioCoachConfiguration =
                snapshot.audioCoach
            self.structuredRunningWorkout =
                snapshot
                    .structuredRunningWorkout
            self.structuredStepIndex =
                snapshot.structuredStepIndex
            self.lapSummaries =
                snapshot.lapSummaries
            self.lapCount =
                snapshot.lapCount
            self.automaticPauseCount =
                snapshot
                    .automaticPauseCount
            self.automaticPauseEnabled =
                snapshot
                    .automaticPauseEnabled ??
                false
            self.strengthSession =
                snapshot.strengthSession
            self.ghostRaceTitle =
                snapshot.ghostRace?.title
        }

        autoPauseDetector.reset(
            enabled:
                snapshot
                    .automaticPauseEnabled ??
                false,
            paused:
                automaticPauseActive
        )
        resetAudioCoachThresholds()
        resetGhostAnnouncementThresholds(
            audio:
                snapshot.ghostRace?.audio
        )
    }

    private func clearPersistedWorkoutState() {
        UserDefaults.standard.removeObject(
            forKey: recoveryDefaultsKey
        )
    }

    func start(
        kind: WatchWorkoutKind,
        route: WatchRouteTransfer? = nil
    ) async {
        workoutInitiatedLocallyOnWatch = true
        prepareForLocalWorkoutStart()

        if kind == .strength {
            ensureStandaloneStrengthSession()
            markStandaloneStrengthStarted()
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType(for: kind)
        configuration.locationType = kind.usesOutdoorLocation ? .outdoor : .indoor

        await start(
            configuration: configuration,
            kind: kind,
            route: route
        )
    }

    private func prepareForLocalWorkoutStart() {
        ghostRaceConfiguration = nil
        cachePlannedRouteGeometry(nil)

        publish {
            self.audioCoachConfiguration = .disabled
            self.structuredRunningWorkout = nil
            self.treadmillInclinePercent = nil
            self.structuredStepIndex = 0
            self.plannedRoute = nil
            self.routeProgressPercent = nil
            self.routeRemainingMeters = nil
            self.routeDeviationMeters = nil
            self.routeDistanceToStartMeters = nil
            self.routeAlertConfiguration = .standard
            self.targetAlertConfiguration = nil
            self.liveTargetStatus = nil
            self.ghostRaceTitle = nil
            self.ghostDistanceDeltaMeters = nil
            self.ghostTimeDeltaSeconds = nil
            self.ghostMapUserLatitude = nil
            self.ghostMapUserLongitude = nil
            self.ghostMapLatitude = nil
            self.ghostMapLongitude = nil
            self.ghostMapRevision = 0
        }

        resetAudioCoachThresholds()
        resetGhostAnnouncementThresholds(
            audio: nil
        )
    }

    func start(configuration: HKWorkoutConfiguration) async {
        workoutInitiatedLocallyOnWatch = false
        let resolvedKind = kind(for: configuration.activityType)
        await start(
            configuration: configuration,
            kind: resolvedKind,
            route: nil
        )
    }

    func pause() {
        guard state == .running else { return }
        manualPauseActive = true
        automaticPauseActive = false
        autoPauseDetector.reset(
            enabled: false
        )
        workoutSession?.pause()
    }

    func resume() {
        guard state == .paused else { return }
        manualPauseActive = false
        autoPauseDetector.reset(
            enabled: automaticPauseEnabled
        )
        workoutSession?.resume()
    }

    func end() {
        guard isActive else { return }
        publishState(.ending)
        workoutSession?.end()
    }

    func reset() {
        stopTimer()
        workoutSession = nil
        workoutBuilder = nil
        routeBuilder = nil
        workoutLocation = nil
        workoutLocationMetadataAttached = false
        startedAt = nil
        finishing = false
        mirroringActive = false
        mirroringRetryPending = false
        lastMirrorSnapshotSentAt = nil
        nextDistanceAnnouncementMeters = nil
        nextTimeAnnouncementSeconds = nil
        structuredStepStartElapsedTime = 0
        structuredStepStartDistanceMeters = 0
        structuredWorkoutComplete = false
        plannedRouteLocations = []
        plannedRouteCumulativeMeters = []
        plannedRouteGeometryMeters = 0
        ghostRaceConfiguration = nil
        nextGhostDistanceAnnouncementMeters = nil
        nextGhostTimeAnnouncementSeconds = nil
        lastGhostAnnouncedLeadMeters = nil
        lastGhostLeadAlertAt = nil
        lastGhostLeadSign = 0
        offRouteStartedAt = nil
        lastOffRouteAlertAt = nil
        routeWasOff = false
        targetViolationStartedAt = nil
        lastTargetAlertAt = nil
        targetWasOutside = false
        lastLapElapsedTime = 0
        lastLapDistanceMeters = 0
        lapSummaries = []
        automaticPauseActive = false
        automaticPauseEnabled = false
        automaticPauseCount = 0
        manualPauseActive = false
        autoPauseDetector.reset(enabled: false)
        capturedRouteLocations = []
        lastRenderedRouteLocation = nil
        gpsFallbackDistanceMeters = 0
        lastAcceptedOutdoorLocation = nil
        healthKitDistanceMeters = 0
        healthKitDistanceLastUpdatedAt = nil
        speechSynthesizer.stopSpeaking(at: .immediate)
        deactivateAudioCoachAudioSession()
        audioCoachReadyAnnouncedForWorkout = false
        strengthCommandJournal = []
        guidancePriorityGate.reset()
        publish {
            self.state = .idle
            self.elapsedTime = 0
            self.heartRate = 0
            self.activeCalories = 0
            self.distanceMeters = 0
            self.currentPaceSecondsPerKilometer = nil
            self.routeProgressPercent = nil
            self.routeRemainingMeters = nil
            self.routeDeviationMeters = nil
            self.routeDistanceToStartMeters = nil
            self.routeAlertConfiguration = .standard
            self.targetAlertConfiguration = nil
            self.liveTargetStatus = nil
            self.ghostRaceTitle = nil
            self.ghostDistanceDeltaMeters = nil
            self.ghostTimeDeltaSeconds = nil
            self.lapCount = 0
            self.currentLapElapsedTime = 0
            self.currentLapDistanceMeters = 0
            self.lapSummaries = []
            self.automaticPauseActive = false
            self.automaticPauseEnabled = false
            self.automaticPauseCount = 0
            self.averageHeartRate = nil
            self.maxHeartRate = nil
            self.routePoints = []
            self.plannedRoute = nil
            self.audioCoachConfiguration = .disabled
            self.structuredRunningWorkout = nil
            self.treadmillInclinePercent = nil
            self.structuredStepIndex = 0
            self.strengthSession = nil
            self.strengthActionPending = false
            self.liveSurfaceContext = .empty
            self.completedResult = nil
            self.errorMessage = nil
        }

        strengthRestCoachTask?.cancel()
        strengthRestCoachTask = nil
        strengthStatusCoachTask?.cancel()
        strengthStatusCoachTask = nil

        clearPersistedWorkoutState()
    }

    private func start(
        configuration: HKWorkoutConfiguration,
        kind: WatchWorkoutKind,
        route: WatchRouteTransfer?
    ) async {
        guard !isActive, state != .preparing, state != .ending else { return }

        let resolvedRoute = route ?? plannedRoute
        cachePlannedRouteGeometry(resolvedRoute)

        publish {
            // Keep any launch payload already delivered by iPhone. The old
            // implementation cleared Audio Coach / structured running data
            // here, creating a race with WatchConnectivity during launch.
            self.structuredStepIndex = 0
            self.strengthSession =
                kind == .strength
                    ? self.strengthSession
                    : nil
            self.state = .preparing
            self.kind = kind
            self.plannedRoute = resolvedRoute
            self.completedResult = nil
            self.errorMessage = nil
            self.elapsedTime = 0
            self.heartRate = 0
            self.activeCalories = 0
            self.distanceMeters = 0
            self.currentPaceSecondsPerKilometer = nil
            self.routeProgressPercent =
                resolvedRoute == nil ? nil : 0
            self.routeRemainingMeters =
                resolvedRoute.map {
                    max(
                        $0.distanceKilometers * 1_000,
                        0
                    )
                }
            self.routeDeviationMeters = nil
            self.routeDistanceToStartMeters = nil
            self.liveTargetStatus = nil
            self.lapCount = 0
            self.currentLapElapsedTime = 0
            self.currentLapDistanceMeters = 0
            self.averageHeartRate = nil
            self.maxHeartRate = nil
            self.routePoints = []
        }
        workoutLocation = nil
        workoutLocationMetadataAttached = false
        structuredStepStartElapsedTime = 0
        structuredStepStartDistanceMeters = 0
        structuredWorkoutComplete = false
        lastLapElapsedTime = 0
        lastLapDistanceMeters = 0
        lapSummaries = []
        automaticPauseActive = false
        automaticPauseCount = 0
        manualPauseActive = false
        autoPauseDetector.reset(
            enabled:
                (kind == .running ||
                 kind == .walking) &&
                automaticPauseEnabled
        )
        capturedRouteLocations = []
        lastRenderedRouteLocation = nil
        gpsFallbackDistanceMeters = 0
        lastAcceptedOutdoorLocation = nil
        healthKitDistanceMeters = 0
        healthKitDistanceLastUpdatedAt = nil
        offRouteStartedAt = nil
        lastOffRouteAlertAt = nil
        routeWasOff = false
        targetViolationStartedAt = nil
        lastTargetAlertAt = nil
        targetWasOutside = false
        audioCoachReadyAnnouncedForWorkout = false
        guidancePriorityGate.reset()
        resetAudioCoachThresholds()

        do {
            try await requestAuthorization()

            let session = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            let builder = session.associatedWorkoutBuilder()

            session.delegate = self
            builder.delegate = self
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            if configuration.locationType == .outdoor,
               let seriesBuilder = builder.seriesBuilder(
                    for: HKSeriesType.workoutRoute()
               ) as? HKWorkoutRouteBuilder {
                routeBuilder = seriesBuilder
            } else {
                routeBuilder = nil
            }

            workoutSession = session
            workoutBuilder = builder
            finishing = false

            let startDate = Date()
            startedAt = startDate
            persistWorkoutRecoveryState()

            do {
                try await session.startMirroringToCompanionDevice()
                mirroringActive = true
                mirroringRetryPending = false
                await sendLiveSnapshot(
                    stateOverride: .preparing,
                    force: true
                )
            } catch {
                // HealthKit can reject the first mirror request while the
                // session is still preparing. The workout itself must still
                // start; retry once after the session reaches .running.
                mirroringActive = false
                mirroringRetryPending = true
            }

            session.startActivity(with: startDate)

            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in

                builder.beginCollection(withStart: startDate) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(
                            throwing: WatchWorkoutError.collectionCouldNotStart
                        )
                    }
                }
            }

            locationManager.requestWhenInUseAuthorization()

            if configuration.locationType == .outdoor {
                locationManager.allowsBackgroundLocationUpdates = true
                locationManager.startUpdatingLocation()
            } else if kind == .strength,
                      locationManager.authorizationStatus == .authorizedWhenInUse ||
                      locationManager.authorizationStatus == .authorizedAlways {
                locationManager.requestLocation()
            }

            publishState(.running)
            WatchHomeAssistantBridge.shared
                .workoutStarted(
                    kind: kind,
                    startedAt: startedAt
                )
            startTimer()

            if kind == .strength {
                requestStrengthSnapshot()
            }

            announceAudioCoachReadyIfNeeded()
            announceCurrentStructuredStep(prefix: "Starting")
        } catch {
            fail(error)
        }
    }

    private func retryMirroringIfNeeded(
        _ session: HKWorkoutSession
    ) async {
        guard mirroringRetryPending,
              !mirroringActive,
              workoutSession === session
        else {
            return
        }

        // Give HealthKit a brief moment after the running-state callback.
        try? await Task.sleep(
            nanoseconds: 350_000_000
        )

        guard mirroringRetryPending,
              !mirroringActive,
              workoutSession === session
        else {
            return
        }

        do {
            try await session.startMirroringToCompanionDevice()
            mirroringActive = true
            mirroringRetryPending = false

            publish {
                if self.errorMessage?
                    .contains("iPhone live") == true {
                    self.errorMessage = nil
                }
            }

            await sendLiveSnapshot(
                stateOverride: .running,
                force: true
            )
        } catch {
            mirroringRetryPending = false
            publish {
                self.errorMessage =
                    "iPhone live metrics unavailable. Workout continues normally on Apple Watch."
            }
        }
    }

    private func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WatchWorkoutError.healthDataUnavailable
        }

        // Match Apple's workout-app authorization model: ATHLTH writes the
        // workout (and route), while live sensor quantities are read by the
        // HKLiveWorkoutDataSource.
        let shareTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        var readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        for identifier in [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling
        ] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                readTypes.insert(type)
            }
        }

        try await healthStore.requestAuthorization(
            toShare: shareTypes,
            read: readTypes
        )

        if healthStore.authorizationStatus(
            for: HKObjectType.workoutType()
        ) == .sharingDenied {
            throw WatchWorkoutError
                .workoutAuthorizationDenied
        }
    }

    private func startTimer() {
        stopTimer()

        timer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let builder = self.workoutBuilder
                else {
                    return
                }

                self.elapsedTime = builder.elapsedTime
                self.currentLapElapsedTime =
                    max(
                        builder.elapsedTime -
                        self.lastLapElapsedTime,
                        0
                    )
                self.currentLapDistanceMeters =
                    max(
                        self.distanceMeters -
                        self.lastLapDistanceMeters,
                        0
                    )

                self.evaluateStructuredRunningWorkout()
                self.evaluateWorkoutTargetAlerts()
                self.evaluateAudioCoach()
                await self.sendLiveSnapshot()
            }
        }
    }

    private func resetAudioCoachThresholds() {
        let configuration = audioCoachConfiguration

        if configuration.enabled,
           let interval = configuration.distanceIntervalMeters,
           interval > 0 {
            let completedIntervals =
                floor(distanceMeters / interval)
            nextDistanceAnnouncementMeters =
                (completedIntervals + 1) * interval
        } else {
            nextDistanceAnnouncementMeters = nil
        }

        if configuration.enabled,
           let interval = configuration.timeIntervalSeconds,
           interval > 0 {
            let completedIntervals =
                floor(elapsedTime / interval)
            nextTimeAnnouncementSeconds =
                (completedIntervals + 1) * interval
        } else {
            nextTimeAnnouncementSeconds = nil
        }
    }

    private func announceAudioCoachReadyIfNeeded() {
        guard state == .running,
              audioCoachConfiguration.enabled,
              !audioCoachReadyAnnouncedForWorkout
        else {
            return
        }

        audioCoachReadyAnnouncedForWorkout = true

        guard audioCoachConfiguration
            .shouldAnnounceWorkoutStart
        else {
            return
        }

        WKInterfaceDevice.current().play(.click)

        speak(
            coachPhrase(
                english:
                    "Audio Coach ready. Workout started.",
                norwegian:
                    "Audio Coach er klar. Økten er startet."
            ),
            priority: .routineCoach
        )
    }

    private func evaluateAudioCoach() {
        guard state == .running,
              audioCoachConfiguration.enabled
        else {
            return
        }

        var shouldAnnounce = false

        if let interval =
                audioCoachConfiguration.distanceIntervalMeters,
           interval > 0,
           let nextDistance = nextDistanceAnnouncementMeters,
           distanceMeters >= nextDistance {
            repeat {
                nextDistanceAnnouncementMeters =
                    (nextDistanceAnnouncementMeters ?? nextDistance) +
                    interval
            } while distanceMeters >=
                (nextDistanceAnnouncementMeters ?? .greatestFiniteMagnitude)

            shouldAnnounce = true
        }

        if let interval =
                audioCoachConfiguration.timeIntervalSeconds,
           interval > 0,
           let nextTime = nextTimeAnnouncementSeconds,
           elapsedTime >= nextTime {
            repeat {
                nextTimeAnnouncementSeconds =
                    (nextTimeAnnouncementSeconds ?? nextTime) +
                    interval
            } while elapsedTime >=
                (nextTimeAnnouncementSeconds ?? .greatestFiniteMagnitude)

            shouldAnnounce = true
        }

        if shouldAnnounce {
            WKInterfaceDevice.current().play(.click)
            speak(
                metricsAnnouncement,
                priority: .routineCoach
            )
        }
    }

    private func evaluateStructuredRunningWorkout() {
        guard state == .running,
              (kind == .running || kind == .walking),
              !structuredWorkoutComplete,
              let step = currentStructuredRunningStep
        else {
            return
        }

        guard ATHLTHRunningStepEngine
            .isCompleted(
                step: step,
                elapsedTime: elapsedTime,
                distanceMeters: distanceMeters,
                stepStartElapsedTime:
                    structuredStepStartElapsedTime,
                stepStartDistanceMeters:
                    structuredStepStartDistanceMeters
            )
        else {
            return
        }

        advanceStructuredRunningWorkout()
    }

    private func advanceStructuredRunningWorkout() {
        guard let workout = structuredRunningWorkout else {
            return
        }

        let nextIndex = structuredStepIndex + 1

        guard workout.steps.indices.contains(nextIndex) else {
            structuredWorkoutComplete = true
            WKInterfaceDevice.current().play(.success)
            if audioCoachConfiguration.enabled &&
                audioCoachConfiguration.announceCurrentWorkoutStep {
                speak(
                    coachPhrase(
                        english:
                            "Structured workout complete. Continue easy or finish your workout when ready.",
                        norwegian:
                            "Den strukturerte økten er fullført. Fortsett rolig eller avslutt økten når du er klar."
                    ),
                    priority:
                        .structuredStep
                )
            }
            return
        }

        structuredStepStartElapsedTime = elapsedTime
        structuredStepStartDistanceMeters = distanceMeters

        targetViolationStartedAt = nil
        lastTargetAlertAt = nil
        targetWasOutside = false

        publish {
            self.structuredStepIndex = nextIndex
            self.liveTargetStatus = nil
        }

        persistWorkoutRecoveryState()
        WKInterfaceDevice.current().play(.notification)
        announceCurrentStructuredStep(prefix: "Next")
    }

    private func announceCurrentStructuredStep(
        prefix: String
    ) {
        guard audioCoachConfiguration.enabled,
              audioCoachConfiguration.announceCurrentWorkoutStep,
              let step = currentStructuredRunningStep
        else {
            return
        }

        let localizedPrefix: String = {
            switch prefix {
            case "Starting":
                return coachPhrase(
                    english: "Starting",
                    norwegian: "Starter"
                )
            case "Next":
                return coachPhrase(
                    english: "Next",
                    norwegian: "Neste"
                )
            case "Current":
                return coachPhrase(
                    english: "Current",
                    norwegian: "Nå"
                )
            default:
                return prefix
            }
        }()

        var parts = [
            localizedPrefix,
            step.title
        ]

        if let target = spokenTarget(for: step) {
            parts.append(target)
        }

        if let intensity = step.intensityText,
           !intensity.isEmpty {
            parts.append(intensity)
        }

        speak(
            parts.joined(separator: ". "),
            priority: .structuredStep
        )
    }

    private func spokenTarget(
        for step: WatchRunningWorkoutStep
    ) -> String? {
        switch step.measure {
        case .distance:
            guard let meters = step.distanceMeters else {
                return nil
            }

            if meters >= 1_000 {
                return String(
                    format: "%.1f kilometers",
                    meters / 1_000
                )
            }

            return "\(Int(meters.rounded())) meters"

        case .time:
            guard let seconds = step.durationSeconds else {
                return nil
            }
            return spokenDuration(seconds)

        case .open:
            return "Open duration"
        }
    }

    private var metricsAnnouncement: String {
        var parts: [String] = []
        let configuration = audioCoachConfiguration

        if configuration.announceDistance,
           distanceMeters > 0 {
            parts.append(
                coachPhrase(
                    english: "Distance",
                    norwegian: "Distanse"
                ) + " " +
                spokenDistance(distanceMeters)
            )
        }

        if configuration.announceElapsedTime {
            parts.append(
                coachPhrase(
                    english: "Elapsed time",
                    norwegian: "Tid"
                ) + " " +
                spokenDuration(elapsedTime)
            )
        }

        let averageSecondsPerKilometer:
            TimeInterval? = {
            guard distanceMeters >= 100,
                  elapsedTime > 0
            else {
                return nil
            }

            return elapsedTime /
                (distanceMeters / 1_000)
        }()

        if configuration.announceAveragePace,
           let averageSecondsPerKilometer {
            parts.append(
                coachPhrase(
                    english: "Average pace",
                    norwegian: "Gjennomsnittstempo"
                ) + " " +
                spokenPace(averageSecondsPerKilometer)
            )
        }

        if configuration.announceHeartRate,
           heartRate > 0 {
            parts.append(
                coachPhrase(
                    english: "Heart rate",
                    norwegian: "Puls"
                ) + " " +
                "\(Int(heartRate.rounded())) " +
                coachPhrase(
                    english: "beats per minute",
                    norwegian: "slag per minutt"
                )
            )
        }

        if configuration.announceClockTime {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            parts.append(
                coachPhrase(
                    english: "Time",
                    norwegian: "Klokken"
                ) + " " +
                formatter.string(from: Date())
            )
        }

        if let totalRouteMeters =
                configuration.routeDistanceMeters,
           totalRouteMeters > 0 {
            let remainingMeters =
                routeRemainingMeters ??
                max(
                    totalRouteMeters - distanceMeters,
                    0
                )

            if configuration
                .announceRemainingRouteDistance {
                parts.append(
                    coachPhrase(
                        english: "Remaining distance",
                        norwegian: "Gjenstående distanse"
                    ) + " " +
                    spokenDistance(remainingMeters)
                )
            }

            if configuration
                .announceEstimatedRemainingRouteTime,
               let averageSecondsPerKilometer,
               remainingMeters > 0 {
                let estimatedRemaining =
                    averageSecondsPerKilometer *
                    (remainingMeters / 1_000)

                parts.append(
                    coachPhrase(
                        english: "Estimated time remaining",
                        norwegian: "Estimert tid igjen"
                    ) + " " +
                    spokenDuration(estimatedRemaining)
                )
            }
        }

        if let step = currentStructuredRunningStep {
            let elapsedInStep =
                max(
                    elapsedTime -
                    structuredStepStartElapsedTime,
                    0
                )
            let distanceInStep =
                max(
                    distanceMeters -
                    structuredStepStartDistanceMeters,
                    0
                )

            if configuration
                .announceRemainingStepTime,
               step.measure == .time,
               let target = step.durationSeconds {
                let remaining = max(
                    target - elapsedInStep,
                    0
                )
                parts.append(
                    coachPhrase(
                        english: "Time remaining in this step",
                        norwegian: "Tid igjen i denne delen"
                    ) + " " +
                    spokenDuration(remaining)
                )
            }

            if configuration
                .announceRemainingStepDistance,
               step.measure == .distance,
               let target = step.distanceMeters {
                let remaining = max(
                    target - distanceInStep,
                    0
                )
                parts.append(
                    coachPhrase(
                        english: "Distance remaining in this step",
                        norwegian: "Distanse igjen i denne delen"
                    ) + " " +
                    spokenDistance(remaining)
                )
            }
        }

        return parts.joined(separator: ". ")
    }

    var currentLapPaceSecondsPerKilometer: TimeInterval? {
        guard currentLapDistanceMeters >= 50,
              currentLapElapsedTime > 0
        else {
            return nil
        }

        return currentLapElapsedTime /
            (currentLapDistanceMeters / 1_000)
    }

    private func cachePlannedRouteGeometry(
        _ route: WatchRouteTransfer?
    ) {
        guard let route,
              route.points.count >= 2
        else {
            plannedRouteLocations = []
            plannedRouteCumulativeMeters = []
            plannedRouteGeometryMeters = 0
            return
        }

        let locations =
            route.points
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

    private func updateOutdoorMetrics(
        using location: CLLocation
    ) {
        guard kind == .running ||
                kind == .walking
        else {
            return
        }

        if location.speed >= 0.35 {
            let rawPace =
                1_000 / location.speed

            if rawPace >= 120,
               rawPace <= 1_800 {
                let smoothed: TimeInterval

                if let existing =
                        currentPaceSecondsPerKilometer {
                    smoothed =
                        existing * 0.72 +
                        rawPace * 0.28
                } else {
                    smoothed = rawPace
                }

                publish {
                    self.currentPaceSecondsPerKilometer =
                        smoothed
                }
            }
        }

        updateRouteNavigation(
            using: location
        )
    }

    private func updateRouteNavigation(
        using location: CLLocation
    ) {
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
                        plannedRoute.map {
                            max(
                                $0.distanceKilometers *
                                    1_000,
                                0
                            )
                        }
                )
        else {
            return
        }

        publish {
            self.routeProgressPercent =
                guidance.progressPercent
            self.routeRemainingMeters =
                guidance.remainingMeters
            self.routeDeviationMeters =
                guidance.deviationMeters
            self.routeDistanceToStartMeters =
                guidance.distanceToStartMeters
        }

        updateGhostRace(
            traveledAlongRoute:
                guidance.traveledAlongRouteMeters,
            userLocation:
                location
        )

        evaluateRouteAlert(
            deviationMeters:
                guidance.deviationMeters,
            horizontalAccuracy:
                location.horizontalAccuracy
        )
    }

    private func updateGhostRace(
        traveledAlongRoute: Double,
        userLocation: CLLocation
    ) {
        guard let ghost =
                ghostRaceConfiguration,
              !ghost.points.isEmpty
        else {
            return
        }

        let targetTime =
            max(elapsedTime, 0)

        var timeLow = 0
        var timeHigh =
            ghost.points.count - 1

        while timeLow < timeHigh {
            let mid =
                (timeLow + timeHigh + 1) / 2

            if ghost.points[mid]
                .elapsedTime <= targetTime {
                timeLow = mid
            } else {
                timeHigh = mid - 1
            }
        }

        let ghostAtTime =
            ghost.points[timeLow]

        let userDistance =
            min(
                max(
                    traveledAlongRoute,
                    0
                ),
                max(
                    ghost.routeDistanceMeters,
                    1
                )
            )

        var nearest =
            ghost.points[0]
        var nearestDifference =
            abs(
                nearest.cumulativeMeters -
                userDistance
            )

        for point in ghost.points {
            let difference =
                abs(
                    point.cumulativeMeters -
                    userDistance
                )

            if difference <
                nearestDifference {
                nearest = point
                nearestDifference =
                    difference
            }
        }

        let distanceDelta =
            userDistance -
            ghostAtTime.cumulativeMeters
        let timeDelta =
            nearest.elapsedTime -
            self.elapsedTime

        publish {
            self.ghostDistanceDeltaMeters =
                distanceDelta
            self.ghostTimeDeltaSeconds =
                timeDelta
        }

        publishGhostMapPositionIfNeeded(
            userLocation:
                userLocation,
            ghostDistanceMeters:
                ghostAtTime
                    .cumulativeMeters,
            routeDistanceMeters:
                ghost
                    .routeDistanceMeters
        )

        evaluateGhostRaceCoach(
            configuration:
                ghost.audio,
            userDistance:
                userDistance,
            distanceDelta:
                distanceDelta,
            timeDelta:
                timeDelta
        )
    }

    private func publishGhostMapPositionIfNeeded(
        userLocation: CLLocation,
        ghostDistanceMeters: Double,
        routeDistanceMeters: Double
    ) {
        guard plannedRouteLocations.count >= 2,
              plannedRouteCumulativeMeters.count ==
                plannedRouteLocations.count,
              plannedRouteGeometryMeters > 0,
              routeDistanceMeters > 0
        else {
            return
        }

        let now = Date()
        if let lastGhostMapPublishedAt,
           now.timeIntervalSince(
                lastGhostMapPublishedAt
           ) < 0.85 {
            return
        }

        let progress =
            min(
                max(
                    ghostDistanceMeters /
                    routeDistanceMeters,
                    0
                ),
                1
            )
        let targetGeometryMeters =
            plannedRouteGeometryMeters *
            progress

        guard let ghostLocation =
                interpolatedPlannedRouteLocation(
                    atGeometryMeters:
                        targetGeometryMeters
                )
        else {
            return
        }

        lastGhostMapPublishedAt = now

        publish {
            self.ghostMapUserLatitude =
                userLocation.coordinate.latitude
            self.ghostMapUserLongitude =
                userLocation.coordinate.longitude
            self.ghostMapLatitude =
                ghostLocation.coordinate.latitude
            self.ghostMapLongitude =
                ghostLocation.coordinate.longitude
            self.ghostMapRevision &+= 1
        }
    }

    private func interpolatedPlannedRouteLocation(
        atGeometryMeters target:
            Double
    ) -> CLLocation? {
        guard plannedRouteLocations.count >= 2,
              plannedRouteCumulativeMeters.count ==
                plannedRouteLocations.count
        else {
            return nil
        }

        let clamped =
            min(
                max(
                    target,
                    0
                ),
                plannedRouteGeometryMeters
            )

        guard let upperIndex =
                plannedRouteCumulativeMeters
                    .firstIndex(
                        where: {
                            $0 >= clamped
                        }
                    )
        else {
            return plannedRouteLocations.last
        }

        if upperIndex == 0 {
            return plannedRouteLocations[0]
        }

        let lowerIndex =
            upperIndex - 1
        let lowerDistance =
            plannedRouteCumulativeMeters[
                lowerIndex
            ]
        let upperDistance =
            plannedRouteCumulativeMeters[
                upperIndex
            ]
        let span =
            max(
                upperDistance -
                lowerDistance,
                0.001
            )
        let fraction =
            min(
                max(
                    (
                        clamped -
                        lowerDistance
                    ) / span,
                    0
                ),
                1
            )

        let lower =
            plannedRouteLocations[
                lowerIndex
            ].coordinate
        let upper =
            plannedRouteLocations[
                upperIndex
            ].coordinate

        return CLLocation(
            latitude:
                lower.latitude +
                (
                    upper.latitude -
                    lower.latitude
                ) *
                fraction,
            longitude:
                lower.longitude +
                (
                    upper.longitude -
                    lower.longitude
                ) *
                fraction
        )
    }

    private func evaluateGhostRaceCoach(
        configuration:
            WatchGhostRaceAudioConfiguration?,
        userDistance: Double,
        distanceDelta: Double,
        timeDelta: TimeInterval?
    ) {
        guard state == .running,
              let configuration,
              configuration.enabled
        else {
            return
        }

        var periodicAnnouncement = false

        if let interval =
                configuration.distanceIntervalMeters,
           interval > 0,
           let next =
                nextGhostDistanceAnnouncementMeters,
           userDistance >= next {
            periodicAnnouncement = true

            var updatedNext = next
            repeat {
                updatedNext += interval
            } while userDistance >= updatedNext

            nextGhostDistanceAnnouncementMeters =
                updatedNext
        }

        if let interval =
                configuration.timeIntervalSeconds,
           interval > 0,
           let next =
                nextGhostTimeAnnouncementSeconds,
           elapsedTime >= next {
            periodicAnnouncement = true

            var updatedNext = next
            repeat {
                updatedNext += interval
            } while elapsedTime >= updatedNext

            nextGhostTimeAnnouncementSeconds =
                updatedNext
        }

        if periodicAnnouncement {
            announceGhostRaceLead(
                distanceDelta:
                    distanceDelta,
                timeDelta:
                    timeDelta,
                delivery:
                    configuration
                        .resolvedPeriodicDelivery,
                priority:
                    .ghostPeriodic
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
              elapsedTime >= 20
        else {
            return
        }

        let currentSign =
            ghostLeadSign(
                distanceDelta
            )
        let signChanged =
            currentSign != 0 &&
            lastGhostLeadSign != 0 &&
            currentSign !=
                lastGhostLeadSign

        let movedEnough =
            lastGhostAnnouncedLeadMeters.map {
                abs(
                    distanceDelta - $0
                ) >=
                max(
                    configuration
                        .leadChangeThresholdMeters,
                    10
                )
            } ?? false

        let cooldownSatisfied =
            lastGhostLeadAlertAt.map {
                Date().timeIntervalSince($0) >=
                    30
            } ?? true

        guard cooldownSatisfied &&
                (signChanged || movedEnough)
        else {
            if lastGhostAnnouncedLeadMeters == nil {
                lastGhostAnnouncedLeadMeters =
                    distanceDelta
                lastGhostLeadSign =
                    currentSign
            }
            return
        }

        let previousLead =
            lastGhostAnnouncedLeadMeters
        let absoluteLeadChange =
            previousLead.map {
                abs(
                    distanceDelta - $0
                )
            } ?? 0
        let important =
            signChanged ||
            absoluteLeadChange >=
                configuration
                    .resolvedImportantLeadChangeMeters

        announceGhostRaceLead(
            distanceDelta:
                distanceDelta,
            timeDelta:
                timeDelta,
            delivery:
                important
                    ? configuration
                        .resolvedImportantLeadChangeDelivery
                    : configuration
                        .resolvedLeadChangeDelivery,
            priority:
                important
                    ? .ghostImportant
                    : .ghostPeriodic
        )

        lastGhostAnnouncedLeadMeters =
            distanceDelta
        lastGhostLeadAlertAt = Date()
        lastGhostLeadSign =
            currentSign
    }

    private func announceGhostRaceLead(
        distanceDelta: Double,
        timeDelta: TimeInterval?,
        delivery: WatchAlertDelivery,
        priority: ATHLTHGuidancePriority
    ) {
        let meters =
            abs(distanceDelta)

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
                    spokenDistance(meters) +
                    " ahead."
            ]
            var norwegianParts = [
                "Spøkelsesløp. Du er " +
                    spokenDistance(meters) +
                    " foran."
            ]

            if let timeDelta {
                englishParts.append(
                    "About " +
                    spokenDuration(
                        abs(timeDelta)
                    ) +
                    " ahead."
                )
                norwegianParts.append(
                    "Omtrent " +
                    spokenDuration(
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
                    spokenDistance(meters) +
                    " ahead."
            ]
            var norwegianParts = [
                "Spøkelsesløp. Spøkelset er " +
                    spokenDistance(meters) +
                    " foran."
            ]

            if let timeDelta {
                englishParts.append(
                    "About " +
                    spokenDuration(
                        abs(timeDelta)
                    ) +
                    " behind."
                )
                norwegianParts.append(
                    "Omtrent " +
                    spokenDuration(
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

        deliverWorkoutAlert(
            english: english,
            norwegian: norwegian,
            delivery: delivery,
            haptic:
                distanceDelta >= 0
                    ? .success
                    : .notification,
            priority: priority
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

    private func evaluateRouteAlert(
        deviationMeters: Double,
        horizontalAccuracy: Double
    ) {
        let configuration =
            routeAlertConfiguration

        guard configuration.enabled,
              horizontalAccuracy >= 0,
              horizontalAccuracy <= 35
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

            if routeWasOff {
                routeWasOff = false

                if configuration
                    .announceBackOnRoute {
                    deliverWorkoutAlert(
                        english: "Back on route",
                        norwegian: "Tilbake på ruten",
                        delivery:
                            configuration.delivery,
                        haptic: .success,
                        priority:
                            .routeCritical
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

        deliverWorkoutAlert(
            english:
                "You are off route. " +
                spokenDistance(deviationMeters),
            norwegian:
                "Du er utenfor ruten. " +
                spokenDistance(deviationMeters),
            delivery:
                configuration.delivery,
            haptic: .directionDown,
            priority:
                .routeCritical
        )
    }

    private func evaluateWorkoutTargetAlerts() {
        guard state == .running,
              kind == .running || kind == .walking,
              let configuration =
                targetAlertConfiguration
        else {
            publish {
                self.liveTargetStatus = nil
            }
            targetViolationStartedAt = nil
            targetWasOutside = false
            return
        }

        var violation:
            (
                english: String,
                norwegian: String
            )?
        var hasEvaluableTarget = false

        if configuration.heartRateEnabled,
           heartRate > 0,
           let minimum =
                configuration
                    .heartRateMinimumBPM,
           let maximum =
                configuration
                    .heartRateMaximumBPM {
            hasEvaluableTarget = true

            if heartRate < minimum {
                violation = (
                    english:
                        "Heart rate below target",
                    norwegian:
                        "Pulsen er under målområdet"
                )
            } else if heartRate > maximum {
                violation = (
                    english:
                        "Heart rate above target",
                    norwegian:
                        "Pulsen er over målområdet"
                )
            }
        }

        if violation == nil,
           configuration.paceAlertsEnabled,
           let pace =
                currentPaceSecondsPerKilometer,
           let step =
                currentStructuredRunningStep {
            let first =
                step
                    .targetPaceMinSecondsPerKilometer
            let second =
                step
                    .targetPaceMaxSecondsPerKilometer

            if first != nil || second != nil {
                hasEvaluableTarget = true

                let low =
                    min(
                        first ?? second ?? pace,
                        second ?? first ?? pace
                    ) -
                    configuration
                        .paceToleranceSecondsPerKilometer
                let high =
                    max(
                        first ?? second ?? pace,
                        second ?? first ?? pace
                    ) +
                    configuration
                        .paceToleranceSecondsPerKilometer

                if pace < low {
                    violation = (
                        english:
                            "Pace faster than target",
                        norwegian:
                            "Tempoet er raskere enn målet"
                    )
                } else if pace > high {
                    violation = (
                        english:
                            "Pace slower than target",
                        norwegian:
                            "Tempoet er saktere enn målet"
                    )
                }
            }
        }

        guard hasEvaluableTarget else {
            publish {
                self.liveTargetStatus = nil
            }
            targetViolationStartedAt = nil
            targetWasOutside = false
            return
        }

        guard let violation else {
            publish {
                self.liveTargetStatus = "On target"
            }
            targetViolationStartedAt = nil

            if targetWasOutside {
                targetWasOutside = false

                if configuration
                    .announceBackInTarget {
                    deliverWorkoutAlert(
                        english: "Back in target",
                        norwegian:
                            "Tilbake i målområdet",
                        delivery:
                            configuration.delivery,
                        haptic: .success,
                        priority:
                            .targetCritical
                    )
                }
            }
            return
        }

        publish {
            self.liveTargetStatus =
                violation.english
        }

        let now = Date()

        if targetViolationStartedAt == nil {
            targetViolationStartedAt = now
        }

        guard now.timeIntervalSince(
            targetViolationStartedAt ?? now
        ) >= configuration.graceSeconds
        else {
            return
        }

        if let lastTargetAlertAt,
           now.timeIntervalSince(
                lastTargetAlertAt
           ) < configuration.repeatSeconds {
            return
        }

        targetWasOutside = true
        lastTargetAlertAt = now

        deliverWorkoutAlert(
            english: violation.english,
            norwegian: violation.norwegian,
            delivery:
                configuration.delivery,
            haptic: .notification,
            priority:
                .targetCritical
        )
    }

    private func deliverWorkoutAlert(
        english: String,
        norwegian: String,
        delivery: WatchAlertDelivery,
        haptic: WKHapticType,
        priority: ATHLTHGuidancePriority
    ) {
        if delivery.usesHaptics,
           liveSurfaceConfiguration
                .hapticsEnabled,
           guidancePriorityGate
            .allowsHaptic(
                for: priority
            ) {
            WKInterfaceDevice.current()
                .play(haptic)
        }

        if delivery.usesVoice,
           liveSurfaceConfiguration
                .audioAlertsEnabled {
            speak(
                coachPhrase(
                    english: english,
                    norwegian: norwegian
                ),
                priority: priority
            )
        }
    }

    private func spokenDistance(
        _ meters: Double
    ) -> String {
        if meters >= 1_000 {
            return String(
                format: "%.1f %@",
                meters / 1_000,
                coachPhrase(
                    english: "kilometers",
                    norwegian: "kilometer"
                )
            )
        }

        return "\(Int(meters.rounded())) " +
            coachPhrase(
                english: "meters",
                norwegian: "meter"
            )
    }


    private func spokenDuration(
        _ duration: TimeInterval
    ) -> String {
        let totalSeconds = max(
            Int(duration.rounded()),
            0
        )
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        var parts: [String] = []

        if hours > 0 {
            parts.append(
                "\(hours) " +
                coachPhrase(
                    english: hours == 1 ? "hour" : "hours",
                    norwegian: hours == 1 ? "time" : "timer"
                )
            )
        }

        if minutes > 0 {
            parts.append(
                "\(minutes) " +
                coachPhrase(
                    english:
                        minutes == 1
                            ? "minute"
                            : "minutes",
                    norwegian:
                        minutes == 1
                            ? "minutt"
                            : "minutter"
                )
            )
        }

        if hours == 0,
           seconds > 0 {
            parts.append(
                "\(seconds) " +
                coachPhrase(
                    english:
                        seconds == 1
                            ? "second"
                            : "seconds",
                    norwegian:
                        seconds == 1
                            ? "sekund"
                            : "sekunder"
                )
            )
        }

        return parts.isEmpty
            ? "0 " +
                coachPhrase(
                    english: "seconds",
                    norwegian: "sekunder"
                )
            : parts.joined(separator: " ")
    }

    private func spokenPace(
        _ secondsPerKilometer: TimeInterval
    ) -> String {
        let totalSeconds = max(
            Int(secondsPerKilometer.rounded()),
            0
        )
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        let value: String

        if seconds == 0 {
            value =
                "\(minutes) " +
                coachPhrase(
                    english: "minutes",
                    norwegian: "minutter"
                )
        } else {
            value =
                "\(minutes) " +
                coachPhrase(
                    english: "minutes",
                    norwegian: "minutter"
                ) +
                " \(seconds) " +
                coachPhrase(
                    english: "seconds",
                    norwegian: "sekunder"
                )
        }

        return value + " " +
            coachPhrase(
                english: "per kilometer",
                norwegian: "per kilometer"
            )
    }

    private func coachPhrase(
        english: String,
        norwegian: String
    ) -> String {
        switch audioCoachConfiguration.language {
        case .norwegian:
            return norwegian
        case .system:
            let languageCode =
                Locale.autoupdatingCurrent.language.languageCode?
                    .identifier
            return languageCode == "nb" ||
                languageCode == "nn" ||
                languageCode == "no"
                ? norwegian
                : english
        case .english:
            return english
        }
    }

    private var audioCoachVoiceLanguage: String? {
        switch audioCoachConfiguration.language {
        case .system:
            return nil
        case .english:
            return "en-US"
        case .norwegian:
            return "nb-NO"
        }
    }

    private func speak(
        _ text: String,
        priority:
            ATHLTHGuidancePriority =
                .routineCoach
    ) {
        guard !text.isEmpty else { return }

        if audioCoachConfiguration
                .shouldPreferIPhoneAudioWhenReachable,
           WCSession.isSupported(),
           WCSession.default.activationState ==
                .activated,
           WCSession.default.isReachable {
            // iPhone is actively mirroring this workout and owns spoken
            // guidance while reachable. If reachability drops, Watch resumes
            // Audio Coach automatically on the next cue.
            return
        }

        let audioIsBusy =
            speechSynthesizer.isSpeaking ||
            audioCoachActivationTask != nil

        let decision =
            guidancePriorityGate
                .voiceDecision(
                    for: priority,
                    isSpeaking: audioIsBusy,
                    quietPeriodSeconds:
                        audioCoachConfiguration
                            .resolvedGuidanceQuietPeriodSeconds
                )

        switch decision {
        case .drop:
            return

        case .interruptAndDeliver:
            audioCoachActivationTask?
                .cancel()
            audioCoachActivationTask = nil
            speechSynthesizer.stopSpeaking(
                at: .immediate
            )

        case .deliver:
            break
        }

        let utterance = AVSpeechUtterance(
            string: text
        )

        if let voiceIdentifier =
                audioCoachConfiguration
                    .voiceIdentifier,
           let selectedVoice =
                AVSpeechSynthesisVoice(
                    identifier:
                        voiceIdentifier
                ) {
            utterance.voice =
                selectedVoice
        } else if let audioCoachVoiceLanguage,
                  let voice =
                    AVSpeechSynthesisVoice(
                        language:
                            audioCoachVoiceLanguage
                    ) {
            utterance.voice = voice
        }

        utterance.rate =
            audioCoachConfiguration
                .resolvedSpeechRate
        utterance.volume =
            audioCoachConfiguration
                .resolvedSpeechVolume

        audioCoachActivationTask =
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                let activated =
                    await self
                        .activateAudioCoachAudioSession()

                guard !Task.isCancelled
                else {
                    if activated {
                        self
                            .deactivateAudioCoachAudioSession()
                    }
                    self.audioCoachActivationTask =
                        nil
                    self.guidancePriorityGate
                        .voiceDidFinish()
                    return
                }

                self.audioCoachActivationTask =
                    nil

                guard activated
                else {
                    self.guidancePriorityGate
                        .voiceDidFinish()
                    return
                }

                self.speechSynthesizer
                    .speak(utterance)
            }
    }

    private func activateAudioCoachAudioSession()
        async -> Bool {
        let session =
            AVAudioSession.sharedInstance()
        let options:
            AVAudioSession.CategoryOptions =
                audioCoachConfiguration
                    .shouldDuckOtherAudio
                ? [
                    .duckOthers,
                    .interruptSpokenAudioAndMixWithOthers
                ]
                : [.mixWithOthers]

        do {
            // First preserve normal coach/music mixing. On watchOS the
            // asynchronous activation API is important because the system may
            // need to resolve or authorize the Watch audio route before TTS
            // starts.
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: options
            )

            if try await session.activate(
                options: []
            ) {
                coachAudioSessionIsActive =
                    true
                errorMessage = nil
                return true
            }
        } catch {
            // Fall through to the Watch-specific route policy below.
        }

        do {
            // If the normal mixed route cannot activate, use the long-form
            // Watch route policy. On supported Watch models this can resolve
            // to the built-in speaker; otherwise watchOS may ask the user for
            // an available audio route.
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                policy: .longFormAudio,
                options: []
            )

            if try await session.activate(
                options: []
            ) {
                coachAudioSessionIsActive =
                    true
                errorMessage = nil
                return true
            }

            errorMessage =
                ATHLTHLocalization.choose(
                    english:
                        "Audio Coach could not open an Apple Watch audio route.",
                    norwegian:
                        "Audio Coach kunne ikke åpne en lydutgang på Apple Watch."
                )
            return false
        } catch {
            // Audio Coach must never interrupt or terminate an active workout.
            // Keep the workout alive and surface only a lightweight diagnostic.
            coachAudioSessionIsActive =
                false
            errorMessage =
                "Audio Coach: \(error.localizedDescription)"
            return false
        }
    }

    private func deactivateAudioCoachAudioSession() {
        guard coachAudioSessionIsActive else {
            return
        }

        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            coachAudioSessionIsActive = false
        } catch {
            // Do not surface this as a workout failure. The next coach cue
            // gets another chance to establish a clean temporary session.
            coachAudioSessionIsActive = false
        }
    }

    private func stopTimer() {
        publish {
            self.timer?.invalidate()
            self.timer = nil
        }
    }

    private func finishWorkout(at endDate: Date) {
        guard !finishing, let builder = workoutBuilder else { return }
        finishing = true
        stopTimer()
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false

        updateFinalStatistics(from: builder)

        builder.endCollection(
            withEnd: endDate
        ) { [weak self] success, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    self.fail(error)
                    return
                }

                guard success else {
                    self.fail(
                        WatchWorkoutError.collectionCouldNotEnd
                    )
                    return
                }

                do {
                    guard let workout =
                            try await builder.finishWorkout()
                    else {
                        self.fail(
                            WatchWorkoutError
                                .workoutCouldNotSave
                        )
                        return
                    }

                    self.finishRouteIfNeeded(
                        workout: workout,
                        endDate: endDate
                    )
                } catch {
                    self.fail(error)
                }
            }
        }
    }

    private func finishRouteIfNeeded(
        workout: HKWorkout,
        endDate: Date
    ) {
        guard let routeBuilder, !routePoints.isEmpty else {
            complete(workout: workout, endDate: endDate)
            return
        }

        routeBuilder.finishRoute(
            with: workout,
            metadata: nil
        ) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    self.errorMessage =
                        "Workout saved, but the GPS route could not be attached: \(error.localizedDescription)"
                }

                self.complete(
                    workout: workout,
                    endDate: endDate
                )
            }
        }
    }

    private func complete(
        workout: HKWorkout,
        endDate: Date
    ) {
        let start =
            startedAt ?? workout.startDate
        let routeCompletion =
            routeCompletionAnalysis()

        var result = WatchWorkoutResult(
            id: UUID(),
            kind: kind,
            healthKitWorkoutUUID: workout.uuid,
            startedAt: start,
            endedAt: endDate,
            duration:
                max(
                    workout.duration,
                    elapsedTime
                ),
            activeCalories: activeCalories,
            distanceMeters: distanceMeters,
            averageHeartRate:
                averageHeartRate,
            maxHeartRate: maxHeartRate,
            routePointCount:
                max(
                    capturedRouteLocations.count,
                    routePoints.count
                ),
            lapSummaries:
                lapSummaries,
            automaticPauseCount:
                automaticPauseCount,
            routeMatchPercent:
                routeCompletion?
                    .routeMatchPercent,
            routeAverageDeviationMeters:
                routeCompletion?
                    .averageDeviationMeters,
            routeMaxDeviationMeters:
                routeCompletion?
                    .maxDeviationMeters,
            routeLeaderboardEligible:
                routeCompletion?
                    .leaderboardEligible,
            routeComparisonID:
                plannedRoute?
                    .comparisonRouteID ??
                plannedRoute?.id,
            routeTitle:
                plannedRoute?.title
        )

        if kind == .strength {
            result.strengthSnapshot =
                strengthSession
            result.strengthCommands =
                strengthCommandJournal
        }

        sendToPhone(result)

        if audioCoachConfiguration.enabled,
           audioCoachConfiguration
            .shouldAnnounceWorkoutComplete {
            speak(
                coachPhrase(
                    english: "Workout complete.",
                    norwegian: "Økten er fullført."
                ),
                priority:
                    .structuredStep
            )
        }

        publish {
            self.completedResult = result
            self.elapsedTime =
                result.duration
            self.state = .completed
            self.automaticPauseActive =
                false
        }
        WatchHomeAssistantBridge.shared
            .workoutStopped()
        clearPersistedWorkoutState()

        Task { @MainActor [weak self] in
            guard let self else { return }

            await self.sendLiveSnapshot(
                stateOverride: .completed,
                force: true
            )

            if self.mirroringActive,
               let workoutSession =
                    self.workoutSession {
                try? await workoutSession
                    .stopMirroringToCompanionDevice()
                self.mirroringActive = false
            }
        }
    }

    private func routeCompletionAnalysis()
        -> ATHLTHRouteCompletionAnalysis?
    {
        guard let route = plannedRoute,
              route.points.count >= 2
        else {
            return nil
        }

        let actual: [CLLocation]

        if capturedRouteLocations.count >= 2 {
            actual = capturedRouteLocations
        } else {
            guard routePoints.count >= 2 else {
                return nil
            }

            actual =
                routePoints
                    .sorted {
                        $0.sequence < $1.sequence
                    }
                    .map {
                        CLLocation(
                            latitude:
                                $0.latitude,
                            longitude:
                                $0.longitude
                        )
                    }
        }
        let reference =
            route.points
                .sorted {
                    $0.sequence < $1.sequence
                }
                .map {
                    CLLocation(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                }

        return ATHLTHRouteCompletionAnalyzer
            .analyze(
                actualLocations: actual,
                referenceLocations:
                    reference
            )
    }

    private func sendToPhone(_ result: WatchWorkoutResult) {
        guard
            WCSession.isSupported(),
            let data = try? JSONEncoder().encode(result)
        else {
            return
        }

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind:
                WatchTransferKind.workoutResult.rawValue,
            WatchTransferMetadataKey.payload:
                data,
            WatchTransferMetadataKey.sentAt:
                Date().timeIntervalSince1970
        ]

        let session = WCSession.default

        // Keep a durable copy even when the iPhone is currently
        // reachable. HealthKit finalization can outlive the foreground
        // connection by several seconds, so relying on sendMessage alone can
        // lose the completion handshake when reachability changes at the
        // wrong moment. The iPhone de-duplicates results by result.id.
        session.transferUserInfo(
            payload
        )

        if session.activationState == .activated,
           session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: nil,
                errorHandler: nil
            )
        }
    }

    nonisolated private static func makeWorkoutResultFallbackHandler(
        payload: [String: Any]
    ) -> (Error) -> Void {
        { _ in
            WCSession.default
                .transferUserInfo(payload)
        }
    }

    private func sendLiveSnapshot(
        stateOverride: WatchWorkoutMirrorState? = nil,
        force: Bool = false
    ) async {
        guard mirroringActive, let workoutSession else { return }

        let now = Date()

        if !force,
           let lastMirrorSnapshotSentAt,
           now.timeIntervalSince(lastMirrorSnapshotSentAt) < 0.85 {
            return
        }

        let latestRoutePoint =
            routePoints.last
        let currentRunningStep =
            currentStructuredRunningStep
        let runningStepProgress =
            currentRunningStep.map {
                ATHLTHRunningStepEngine.progress(
                    step: $0,
                    elapsedTime: elapsedTime,
                    distanceMeters: distanceMeters,
                    stepStartElapsedTime:
                        structuredStepStartElapsedTime,
                    stepStartDistanceMeters:
                        structuredStepStartDistanceMeters
                )
            }

        let snapshot = WatchWorkoutLiveSnapshot(
            kind: kind,
            state: stateOverride ?? mirrorState(for: state),
            startedAt: startedAt,
            capturedAt: now,
            elapsedTime: elapsedTime,
            heartRate: heartRate,
            activeCalories: activeCalories,
            distanceMeters: distanceMeters,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            routePointCount: routePoints.count,
            currentLatitude:
                latestRoutePoint?.latitude,
            currentLongitude:
                latestRoutePoint?.longitude,
            routeProgressPercent:
                routeProgressPercent,
            routeComparisonID:
                plannedRoute?
                    .comparisonRouteID ??
                plannedRoute?.id,
            routeTitle:
                plannedRoute?.title,
            routeDistanceMeters:
                plannedRoute.map {
                    max(
                        $0.distanceKilometers *
                            1_000,
                        0
                    )
                },
            workoutDisplayTitle:
                structuredRunningWorkout?.title ??
                plannedRoute?.title ??
                kind.title,
            currentPaceSecondsPerKilometer:
                currentPaceSecondsPerKilometer,
            treadmillInclinePercent:
                treadmillInclinePercent,
            routeRemainingMeters:
                routeRemainingMeters,
            routeDeviationMeters:
                routeDeviationMeters,
            routeDeviationThresholdMeters:
                routeAlertConfiguration.deviationMeters,
            runningStepTitle:
                currentRunningStep?.title,
            runningStepIndex:
                currentRunningStep == nil
                    ? nil
                    : structuredStepIndex,
            runningStepCount:
                structuredRunningWorkout?
                    .steps.count,
            runningStepProgress:
                runningStepProgress,
            runningNextStepTitle:
                nextStructuredRunningStep?.title,
            heartRateTargetZone:
                targetAlertConfiguration?.heartRateZone,
            heartRateTargetMinimumBPM:
                targetAlertConfiguration?
                    .heartRateMinimumBPM,
            heartRateTargetMaximumBPM:
                targetAlertConfiguration?
                    .heartRateMaximumBPM,
            heartRateTargetStatus:
                liveTargetStatus,
            ghostRaceTitle:
                ghostRaceTitle,
            ghostDistanceDeltaMeters:
                ghostDistanceDeltaMeters,
            ghostTimeDeltaSeconds:
                ghostTimeDeltaSeconds,
            strengthExerciseName:
                strengthSession?.exerciseName,
            strengthSetIndex:
                strengthSession.map { $0.setIndex + 1 },
            strengthSetCount:
                strengthSession?.setCount,
            strengthReps:
                strengthSession?.draftReps,
            strengthWeightKilograms:
                strengthSession?.draftWeightKilograms,
            strengthRestEndsAt:
                strengthSession?.restEndsAt,
            liveSurfaceConfiguration:
                liveSurfaceConfiguration,
            liveSurfaceContext:
                liveSurfaceContext
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        do {
            try await workoutSession.sendToRemoteWorkoutSession(data: data)
            lastMirrorSnapshotSentAt = now
        } catch {
            publish {
                self.errorMessage =
                    "iPhone live metrics are temporarily unavailable. Workout continues normally."
            }
        }
    }

    private func mirrorState(
        for state: WatchWorkoutState
    ) -> WatchWorkoutMirrorState {
        switch state {
        case .idle, .preparing:
            return .preparing
        case .running:
            return .running
        case .paused:
            return .paused
        case .ending:
            return .ending
        case .completed:
            return .completed
        case .failed:
            return .failed
        }
    }

    private func updateStatistics(
        _ types: Set<HKSampleType>,
        builder: HKLiveWorkoutBuilder
    ) {
        let heartType = HKObjectType.quantityType(forIdentifier: .heartRate)
        let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        let distanceIdentifier: HKQuantityTypeIdentifier? = {
            switch kind {
            case .running, .walking:
                return .distanceWalkingRunning
            case .cycling:
                return .distanceCycling
            case .strength, .hiit, .functional, .rowing, .stairClimbing, .yoga, .other:
                return nil
            }
        }()
        let distanceType = distanceIdentifier.flatMap {
            HKObjectType.quantityType(forIdentifier: $0)
        }

        if let heartType, types.contains(heartType),
           let statistics = builder.statistics(for: heartType) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            let latest = statistics.mostRecentQuantity()?.doubleValue(for: unit) ?? heartRate
            let average = statistics.averageQuantity()?.doubleValue(for: unit)
            let maximum = statistics.maximumQuantity()?.doubleValue(for: unit)

            publish {
                self.heartRate = latest
                self.averageHeartRate = average ?? self.averageHeartRate
                self.maxHeartRate = maximum ?? self.maxHeartRate
            }
        }

        if let energyType, types.contains(energyType),
           let statistics = builder.statistics(for: energyType),
           let quantity = statistics.sumQuantity() {
            publish {
                self.activeCalories = quantity.doubleValue(for: .kilocalorie())
            }
        }

        if let distanceType, types.contains(distanceType),
           let statistics = builder.statistics(for: distanceType),
           let quantity = statistics.sumQuantity() {
            let healthDistance =
                quantity.doubleValue(for: .meter())

            healthKitDistanceMeters = max(healthDistance, 0)
            healthKitDistanceLastUpdatedAt = Date()

            publish {
                self.distanceMeters = self.healthKitDistanceMeters
            }
        }
    }

    private func updateStatistics(
        identifiers: Set<String>,
        builder: HKLiveWorkoutBuilder
    ) {
        let types = Set(
            identifiers.compactMap {
                identifier -> HKSampleType? in

                if identifier ==
                    HKQuantityTypeIdentifier
                        .heartRate.rawValue {
                    return HKObjectType
                        .quantityType(
                            forIdentifier:
                                .heartRate
                        )
                }

                if identifier ==
                    HKQuantityTypeIdentifier
                        .activeEnergyBurned.rawValue {
                    return HKObjectType
                        .quantityType(
                            forIdentifier:
                                .activeEnergyBurned
                        )
                }

                if identifier ==
                    HKQuantityTypeIdentifier
                        .distanceWalkingRunning.rawValue {
                    return HKObjectType
                        .quantityType(
                            forIdentifier:
                                .distanceWalkingRunning
                        )
                }

                if identifier ==
                    HKQuantityTypeIdentifier
                        .distanceCycling.rawValue {
                    return HKObjectType
                        .quantityType(
                            forIdentifier:
                                .distanceCycling
                        )
                }

                return nil
            }
        )

        updateStatistics(
            types,
            builder: builder
        )
    }

    private func updateFinalStatistics(from builder: HKLiveWorkoutBuilder) {
        var types = Set<HKSampleType>()

        for identifier in [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling
        ] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        updateStatistics(types, builder: builder)
    }

    private func activityType(
        for kind: WatchWorkoutKind
    ) -> HKWorkoutActivityType {
        switch kind {
        case .running: return .running
        case .walking: return .walking
        case .strength: return .traditionalStrengthTraining
        case .hiit: return .highIntensityIntervalTraining
        case .functional: return .functionalStrengthTraining
        case .cycling: return .cycling
        case .rowing: return .rowing
        case .stairClimbing: return .stairClimbing
        case .yoga: return .yoga
        case .other: return .other
        }
    }

    private func kind(
        for activityType: HKWorkoutActivityType
    ) -> WatchWorkoutKind {
        switch activityType {
        case .running:
            return .running
        case .walking:
            return .walking
        case .traditionalStrengthTraining:
            return .strength
        case .functionalStrengthTraining:
            return .functional
        case .highIntensityIntervalTraining:
            return .hiit
        case .cycling:
            return .cycling
        case .rowing:
            return .rowing
        case .stairClimbing:
            return .stairClimbing
        case .yoga:
            return .yoga
        default:
            return .other
        }
    }

    private func triggerAutomaticPause() {
        guard automaticPauseEnabled,
              !manualPauseActive,
              !automaticPauseActive,
              state == .running
        else {
            return
        }

        automaticPauseActive = true
        automaticPauseCount += 1
        workoutSession?.pause()
        persistWorkoutRecoveryState()
        WKInterfaceDevice.current().play(.click)
    }

    private func triggerAutomaticResume() {
        guard automaticPauseEnabled,
              !manualPauseActive,
              automaticPauseActive
        else {
            return
        }

        automaticPauseActive = false
        autoPauseDetector.reset(
            enabled: automaticPauseEnabled
        )
        workoutSession?.resume()
        persistWorkoutRecoveryState()
        WKInterfaceDevice.current().play(.click)
    }

    private func handleSystemWorkoutEvent(
        _ type: HKWorkoutEventType
    ) {
        switch type {
        case .pauseOrResumeRequest:
            if state == .running {
                pause()
            } else if state == .paused {
                resume()
            }

        case .motionPaused:
            triggerAutomaticPause()

        case .motionResumed:
            triggerAutomaticResume()

        default:
            break
        }
    }

    private func handleWorkoutSessionState(
        _ state: HKWorkoutSessionState,
        date: Date
    ) {
        let previousState = self.state

        switch state {
        case .running:
            publishState(.running)
            persistWorkoutRecoveryState()

            if kind == .strength {
                requestStrengthSnapshot()
            }

            if previousState == .paused,
               audioCoachConfiguration.enabled,
               audioCoachConfiguration
                .shouldAnnouncePauseResume {
                speak(
                    coachPhrase(
                        english: "Workout resumed.",
                        norwegian: "Økten fortsetter."
                    ),
                    priority:
                        .structuredStep
                )
            }

            Task { @MainActor [weak self] in
                guard let self else { return }

                if let workoutSession =
                    self.workoutSession {
                    await self
                        .retryMirroringIfNeeded(
                            workoutSession
                        )
                }

                await self.sendLiveSnapshot(
                    stateOverride: .running,
                    force: true
                )
            }

        case .paused:
            publishState(.paused)
            persistWorkoutRecoveryState()

            if previousState == .running,
               audioCoachConfiguration.enabled,
               audioCoachConfiguration
                .shouldAnnouncePauseResume {
                speak(
                    coachPhrase(
                        english: "Workout paused.",
                        norwegian:
                            "Økten er satt på pause."
                    ),
                    priority:
                        .structuredStep
                )
            }

            Task { @MainActor [weak self] in
                await self?.sendLiveSnapshot(
                    stateOverride: .paused,
                    force: true
                )
            }

        case .ended:
            publishState(.ending)
            persistWorkoutRecoveryState()

            Task { @MainActor [weak self] in
                await self?.sendLiveSnapshot(
                    stateOverride: .ending,
                    force: true
                )
            }

            finishWorkout(at: date)

        default:
            break
        }
    }

    private func fail(
        message: String
    ) {
        stopTimer()
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        errorMessage = message
        state = .failed(message)
        WatchHomeAssistantBridge.shared
            .workoutStopped()
        clearPersistedWorkoutState()

        Task { @MainActor [weak self] in
            await self?.sendLiveSnapshot(
                stateOverride: .failed,
                force: true
            )
        }
    }

    private func fail(_ error: Error) {
        stopTimer()
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        publish {
            self.errorMessage = error.localizedDescription
            self.state = .failed(error.localizedDescription)
        }
        WatchHomeAssistantBridge.shared
            .workoutStopped()
        clearPersistedWorkoutState()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.sendLiveSnapshot(
                stateOverride: .failed,
                force: true
            )
        }
    }

    private func publishState(_ newState: WatchWorkoutState) {
        publish {
            self.state = newState
        }
    }

    private func publish(
        _ changes: () -> Void
    ) {
        changes()
    }
}

extension WatchWorkoutManager:
    AVSpeechSynthesizerDelegate {

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

            self.guidancePriorityGate
                .voiceDidFinish()
            self.deactivateAudioCoachAudioSession()
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

            self.guidancePriorityGate
                .voiceDidFinish()
            self.deactivateAudioCoachAudioSession()
        }
    }
}

extension WatchWorkoutManager:
    HKWorkoutSessionDelegate {

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let rawState = toState.rawValue

        Task { @MainActor [weak self] in
            guard let self,
                  let state =
                    HKWorkoutSessionState(
                        rawValue: rawState
                    )
            else {
                return
            }

            self.handleWorkoutSessionState(
                state,
                date: date
            )
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didGenerate event: HKWorkoutEvent
    ) {
        let rawType =
            event.type.rawValue

        Task { @MainActor [weak self] in
            guard let self,
                  let type =
                    HKWorkoutEventType(
                        rawValue: rawType
                    )
            else {
                return
            }

            self.handleSystemWorkoutEvent(
                type
            )
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        let message = error.localizedDescription

        Task { @MainActor [weak self] in
            self?.fail(message: message)
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession
            data: [Data]
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            for payload in data {
                guard
                    let command =
                        try? JSONDecoder().decode(
                            WatchWorkoutMirrorCommand.self,
                            from: payload
                        )
                else {
                    continue
                }

                switch command.command {
                case .end:
                    self.end()
                case .pause:
                    self.pause()
                case .resume:
                    self.resume()
                }
            }
        }
    }
}

extension WatchWorkoutManager:
    HKLiveWorkoutBuilderDelegate {

    nonisolated func workoutBuilderDidCollectEvent(
        _ workoutBuilder: HKLiveWorkoutBuilder
    ) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf
            collectedTypes: Set<HKSampleType>
    ) {
        let identifiers =
            Set(
                collectedTypes.map(
                    \.identifier
                )
            )

        Task { @MainActor [weak self] in
            guard let self,
                  let builder =
                    self.workoutBuilder
            else {
                return
            }

            self.updateStatistics(
                identifiers: identifiers,
                builder: builder
            )
        }
    }
}

extension WatchWorkoutManager:
    CLLocationManagerDelegate {

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations
            locations: [CLLocation]
    ) {
        let samples =
            locations
                .filter {
                    $0.horizontalAccuracy >= 0 &&
                    $0.horizontalAccuracy <= 50
                }
                .map(WatchLocationSample.init)

        guard !samples.isEmpty else {
            return
        }

        Task { @MainActor [weak self] in
            self?.handleLocationSamples(
                samples
            )
        }
    }

    nonisolated func
        locationManagerDidChangeAuthorization(
            _ manager: CLLocationManager
        ) {
        let authorized =
            manager.authorizationStatus
                == .authorizedWhenInUse ||
            manager.authorizationStatus
                == .authorizedAlways

        guard authorized else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self,
                  self.state == .running
            else {
                return
            }

            if self.kind.usesOutdoorLocation {
                self.locationManager
                    .allowsBackgroundLocationUpdates =
                    true
                // The initial call can happen while the permission sheet is
                // unresolved. Starting again here makes outdoor tracking
                // deterministic after authorization changes.
                self.locationManager.startUpdatingLocation()
            } else if self.kind == .strength {
                self.locationManager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let message =
            "Location: \(error.localizedDescription)"

        Task { @MainActor [weak self] in
            self?.errorMessage = message
        }
    }
}

private extension WatchWorkoutManager {
    func handleLocationSamples(
        _ samples: [WatchLocationSample]
    ) {
        let filtered =
            samples.map {
                $0.makeLocation()
            }

        guard !filtered.isEmpty else {
            return
        }

        if kind == .strength {
            if let bestLocation =
                filtered.min(
                    by: {
                        $0.horizontalAccuracy <
                        $1.horizontalAccuracy
                    }
                ) {
                workoutLocation = bestLocation
                attachWorkoutLocationMetadataIfPossible()
            }
            return
        }

        let orderedLocations =
            filtered.sorted {
                $0.timestamp < $1.timestamp
            }

        if automaticPauseEnabled &&
            (kind == .running ||
             kind == .walking) {
            for location in orderedLocations {
                if let action =
                        autoPauseDetector.evaluate(
                            location,
                            walking:
                                kind == .walking
                        ) {
                    switch action {
                    case .pause:
                        triggerAutomaticPause()
                    case .resume:
                        triggerAutomaticResume()
                    }
                }
            }
        }

        if automaticPauseActive ||
            state == .paused {
            return
        }

        for location in orderedLocations {
            recordFallbackDistance(
                using: location
            )
        }

        capturedRouteLocations
            .append(
                contentsOf:
                    orderedLocations
            )
        compactCapturedRouteIfNeeded()

        routeBuilder?.insertRouteData(
            filtered
        ) { [weak self] success, error in
            guard !success,
                  let error
            else {
                return
            }

            let message =
                "GPS route update failed: \(error.localizedDescription)"

            Task { @MainActor [weak self] in
                self?.errorMessage = message
            }
        }

        if let latest =
                filtered.max(
                    by: {
                        $0.timestamp <
                        $1.timestamp
                    }
                ) {
            updateOutdoorMetrics(
                using: latest
            )
        }

        for location in orderedLocations {
            appendRenderedRoutePointIfNeeded(
                location
            )
        }
    }

    func compactCapturedRouteIfNeeded() {
        guard capturedRouteLocations.count >
                6_000
        else {
            return
        }

        capturedRouteLocations =
            capturedRouteLocations
                .enumerated()
                .compactMap {
                    index,
                    location in

                    index.isMultiple(of: 2)
                        ? location
                        : nil
                }
    }

    func appendRenderedRoutePointIfNeeded(
        _ location: CLLocation
    ) {
        if let previous =
                lastRenderedRouteLocation {
            let distance =
                location.distance(
                    from: previous
                )
            let interval =
                location.timestamp
                    .timeIntervalSince(
                        previous.timestamp
                    )

            guard distance >= 10 ||
                    interval >= 7
            else {
                return
            }
        }

        lastRenderedRouteLocation =
            location

        routePoints.append(
            WatchRoutePoint(
                latitude:
                    location.coordinate
                        .latitude,
                longitude:
                    location.coordinate
                        .longitude,
                altitude:
                    location.altitude,
                sequence:
                    routePoints.count
            )
        )

        guard routePoints.count > 240
        else {
            return
        }

        routePoints =
            routePoints
                .enumerated()
                .compactMap {
                    index,
                    point in

                    index.isMultiple(of: 2)
                        ? point
                        : nil
                }
                .enumerated()
                .map {
                    index,
                    point in

                    WatchRoutePoint(
                        latitude:
                            point.latitude,
                        longitude:
                            point.longitude,
                        altitude:
                            point.altitude,
                        sequence: index
                    )
                }
    }

    func recordFallbackDistance(
        using location: CLLocation
    ) {
        guard state == .running,
              kind == .running || kind == .walking
        else {
            return
        }

        defer {
            lastAcceptedOutdoorLocation = location
        }

        guard let previous = lastAcceptedOutdoorLocation else {
            return
        }

        let interval =
            location.timestamp.timeIntervalSince(
                previous.timestamp
            )

        guard interval > 0,
              interval <= 20
        else {
            return
        }

        let delta = location.distance(from: previous)
        let maximumReasonableDelta =
            max(45, interval * 12)

        guard delta.isFinite,
              delta >= 0,
              delta <= maximumReasonableDelta
        else {
            return
        }

        gpsFallbackDistanceMeters += delta

        let healthDistanceIsFresh =
            healthKitDistanceLastUpdatedAt.map {
                Date().timeIntervalSince($0) < 8
            } ?? false

        guard !healthDistanceIsFresh else {
            return
        }

        publish {
            self.distanceMeters = max(
                self.healthKitDistanceMeters,
                self.gpsFallbackDistanceMeters
            )
        }
    }

    func attachWorkoutLocationMetadataIfPossible() {
        guard kind == .strength,
              !workoutLocationMetadataAttached,
              let location = workoutLocation,
              let builder = workoutBuilder
        else {
            return
        }

        workoutLocationMetadataAttached = true

        builder.addMetadata([
            ATHLTHWorkoutMetadataKey
                .locationLatitude:
                    location.coordinate.latitude,
            ATHLTHWorkoutMetadataKey
                .locationLongitude:
                    location.coordinate.longitude,
            ATHLTHWorkoutMetadataKey
                .locationHorizontalAccuracy:
                    location.horizontalAccuracy
        ]) { [weak self] success, error in
            guard !success,
                  let error
            else {
                return
            }

            let message =
                "Workout location could not be saved: \(error.localizedDescription)"

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.workoutLocationMetadataAttached =
                    false
                self.errorMessage = message
            }
        }
    }
}

enum WatchWorkoutError: LocalizedError {
    case healthDataUnavailable
    case workoutAuthorizationDenied
    case collectionCouldNotStart
    case collectionCouldNotEnd
    case workoutCouldNotSave

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "HealthKit isn't available on this Apple Watch."
        case .workoutAuthorizationDenied:
            return "Allow ATHLTH to save workouts in Health on Apple Watch, then try again."
        case .collectionCouldNotStart:
            return "ATHLTH couldn't start workout data collection."
        case .collectionCouldNotEnd:
            return "ATHLTH couldn't finish workout data collection."
        case .workoutCouldNotSave:
            return "ATHLTH couldn't save the workout to Apple Health."
        }
    }
}
