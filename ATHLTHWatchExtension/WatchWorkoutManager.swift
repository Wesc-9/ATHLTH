@preconcurrency import AVFoundation
@preconcurrency import CoreLocation
import Foundation
@preconcurrency import HealthKit
@preconcurrency import WatchConnectivity
@preconcurrency import WatchKit

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
    @Published private(set) var companionWorkoutActivity:
        WatchWorkoutActivityState?
    private var lastReportedWorkoutActivity:
        WatchWorkoutActivityState?
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
    @Published private(set) var routeNavigationLatitude: Double?
    @Published private(set) var routeNavigationLongitude: Double?
    @Published private(set) var routeNavigationCourseDegrees: Double?
    @Published private(set) var routeNavigationNearestPointIndex: Int?
    @Published private(set) var routeNavigationRevision = 0
    @Published private(set) var returningToRouteStart = false
    private var routeLegDistanceOffsetMeters: Double = 0
    @Published private(set) var routeAlertConfiguration:
        WatchRouteAlertConfiguration = .standard
    @Published private(set) var targetAlertConfiguration:
        WatchWorkoutTargetAlertConfiguration?
    @Published private(set) var liveTargetStatus: String?
    @Published private(set) var ghostRaceTitle: String?
    @Published private(set) var ghostDistanceDeltaMeters: Double?
    @Published private(set) var ghostTimeDeltaSeconds: TimeInterval?
    @Published private(set) var ghostComparisonUpdatedAt: Date?
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
    @Published private(set) var indoorSuggestionAvailable = false
    @Published private(set) var switchedIndoorVenue: ATHLTHIndoorRunVenue?
    private var indoorPromptedInThisWorkout = false
    private var indoorFirstFix: Date?
    private var indoorLastFix: Date?
    private var indoorFixCount = 0
    private var indoorProbeDistanceMeters = 0.0
    private var indoorPreviousReliableLocation: CLLocation?
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
    @Published private(set) var treadmillTargetPaceSecondsPerKilometer:
        Double?
    @Published private(set) var structuredStepIndex = 0
    @Published private(set) var awaitingMainStart = false
    @Published private(set) var strengthSession:
        WatchStrengthSessionSnapshot?
    @Published private(set) var strengthActionPending = false
    // Optimistic weight edits stay authoritative briefly while the iPhone
    // acknowledges the newest value. Without this, delayed snapshots undo
    // consecutive taps and the Digital Crown appears to bounce.
    private var pendingStrengthWeight: (
        workoutID: UUID, value: Double, changedAt: Date
    )?
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
    private var collectingHybridTreadmillDistance = false
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var workoutLocation: CLLocation?
    private var workoutLocationMetadataAttached = false
    private var timer: Timer?
    private var startedAt: Date?
    private var finishing = false
    private var mirroringActive = false
    private var mirroringRetryPending = false
    private var iPhoneVoiceLease = ATHLTHAudioCoachVoiceLease()
    private var lastMirrorSnapshotSentAt: Date?
    private var appliedRunningAppendCommands = Set<UUID>()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var coachAudioSessionIsActive = false
    private var audioCoachRestorationTask: Task<Void, Never>?
    private var audioCoachSpeechWatchdog: Task<Void, Never>?
    private var audioCoachActivationTask:
        Task<Void, Never>?
    private var audioCoachReadyAnnouncedForWorkout = false
    private var strengthRestCoachTask:
        Task<Void, Never>?
    private var strengthStatusCoachTask:
        Task<Void, Never>?
    private var guidancePriorityGate =
        ATHLTHGuidancePriorityGate()
    private var coachEventLedger = ATHLTHCoachEventLedger()
    private var coachCueQueue = ATHLTHCoachCueQueue()
    /// Temporary voice mute; HealthKit capture and safety haptics continue.
    @Published private(set) var coachSpeechPaused = false
    private var aiConversationVoiceSuppressed = false
    private var coachSpeechWasPausedBeforeAI = false
    private var aiConversationVoiceTimeoutTask: Task<Void, Never>?
    @Published private(set) var lastCoachMessage: String?
    private var coachReplayMemory = ATHLTHCoachReplayMemory()
    private var smartCoachState = ATHLTHAudioCoachSmartState()

    var canReplayLastCoachMessage: Bool {
        audioCoachConfiguration.enabled &&
        !coachSpeechPaused &&
        isActive &&
        coachReplayMemory.replayableText() != nil
    }
    private var nextDistanceAnnouncementMeters: Double?
    private var nextTimeAnnouncementSeconds: TimeInterval?
    private var customAudioCoachLastSlots: [UUID: Int] = [:]
    private var nextFuelAnnouncementSeconds: TimeInterval?
    private var structuredStepStartElapsedTime: TimeInterval = 0
    private var structuredStepStartDistanceMeters: Double = 0
    private var structuredWorkoutComplete = false
    private var recordedStructuredRunSteps: [ATHLTHRecordedRunningStep] = []
    private var recordedStructuredRunMinutes: [ATHLTHRecordedRunningMinute] = []
    private var lastIntervalProgressCueKey: String?
    private var lastIntervalWarningCueKey: String?
    private var plannedRouteLocations: [CLLocation] = []
    private var plannedRouteCumulativeMeters: [Double] = []
    private var plannedRouteGeometryMeters: Double = 0
    private var ghostRaceConfiguration:
        WatchGhostRaceTransfer?

    /// Signed percentage along the course, not travelled workout kilometres.
    /// Positive means runner ahead of the fixed Replay/Target Ghost.
    var ghostRouteGapPercent: Double? {
        guard let ghost = ghostRaceConfiguration,
              let distanceDelta = ghostDistanceDeltaMeters else { return nil }
        return ATHLTHGhostCourseProgressPolicy.ghostLeadPercent(
            runnerCourseMeters: max(distanceDelta, 0),
            ghostCourseMeters: max(-distanceDelta, 0),
            routeLengthMeters: ghost.routeDistanceMeters
        ).map { -$0 }
    }

    var ghostIsOffPlannedRoute: Bool {
        ghostRaceConfiguration != nil && ghostOffRoute
    }
    private var nextGhostDistanceAnnouncementMeters: Double?
    private var nextGhostTimeAnnouncementSeconds: TimeInterval?
    private var lastGhostAnnouncedLeadMeters: Double?
    private var lastGhostLeadAlertAt: Date?
    private var lastGhostLeadSign = 0
    private var ghostOvertakeTracker = ATHLTHGhostLeadTracker()
    private var ghostFinalPhaseAnnounced = false
    private var lastLiveGhostConnectionText: String?
    private var lastGhostMapPublishedAt: Date?
    private var ghostLastTrustedCourseMeters: Double?
    private var ghostLastTrustedCourseElapsed: TimeInterval?
    private var ghostOffRoute = false
    private var ghostReentryReliableSamples = 0
    private var ghostLastAnnouncedGapPercent: Double?
    private var ghostLastGapAlertAt: Date?
    private var lastRouteNavigationMapPublishedAt: Date?
    private var lastSpokenRouteTurnIndex: Int?
    private var lastSpokenRouteTurnAt: Date?
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
    private var coachHeartRateSampleAt: Date?
    private var coachPaceSampleAt: Date?
    private var lastGoalEncouragementAt: Date?

    /// The same sensor freshness gate used by live target alerts and coach.
    /// A disconnected/stale pulse must not be rendered as a live zone.
    var hasFreshHeartRate: Bool {
        ATHLTHCoachSensorFreshness.validHeartRate(
            heartRate,
            sampledAt: coachHeartRateSampleAt
        )
    }
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

    var routeNavigationCue: ATHLTHRouteNavigationCue.Instruction? {
        guard let index = routeNavigationNearestPointIndex,
              let latitude = routeNavigationLatitude,
              let longitude = routeNavigationLongitude,
              let deviation = routeDeviationMeters,
              plannedRouteLocations.count >= 2 else { return nil }
        let route = plannedRouteLocations.map(\.coordinate)
        if routeAlertConfiguration.enabled &&
            deviation > routeAlertConfiguration.deviationMeters {
            return ATHLTHRouteNavigationCue.recovery(
                user: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                courseDegrees: routeNavigationCourseDegrees,
                route: route,
                nearestIndex: index,
                deviationMeters: deviation
            )
        }
        return ATHLTHRouteNavigationCue.nextTurn(
            route: route, nearestIndex: index
        )
    }

    var canRunBackToStart: Bool {
        guard isActive, !returningToRouteStart,
              let route = plannedRoute, route.points.count >= 2,
              let remaining = routeRemainingMeters, remaining <= 125,
              let progress = routeProgressPercent, progress >= 85,
              let latitude = routeNavigationLatitude,
              let longitude = routeNavigationLongitude else { return false }
        let sorted = route.points.sorted { $0.sequence < $1.sequence }
        guard let start = sorted.first, let finish = sorted.last else {
            return false
        }
        let startPoint = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let finishPoint = CLLocation(latitude: finish.latitude, longitude: finish.longitude)
        let current = CLLocation(latitude: latitude, longitude: longitude)
        return startPoint.distance(from: finishPoint) > 60 &&
            current.distance(from: finishPoint) <= 100
    }

    func startReturnToRouteStart() {
        guard canRunBackToStart, let original = plannedRoute else { return }
        let reversed = original.points
            .sorted { $0.sequence < $1.sequence }
            .reversed()
            .enumerated()
            .map { offset, point in
                WatchRoutePoint(latitude: point.latitude, longitude: point.longitude,
                                altitude: point.altitude, sequence: offset)
            }
        let trip = WatchRouteTransfer(
            id: UUID(),
            comparisonRouteID: nil,
            title: ATHLTHLocalization.choose(
                english: "Return to start", norwegian: "Tilbake til start"
            ),
            distanceKilometers: original.distanceKilometers,
            elevationGainMeters: nil,
            points: reversed,
            updatedAt: Date()
        )
        // Keep the HealthKit workout running. Only navigation changes;
        // ghost progress on the original A–B course is no longer comparable.
        disableGhostDuringWorkout()
        routeLegDistanceOffsetMeters = distanceMeters
        returningToRouteStart = true
        configurePlannedRoute(trip)
        lastSpokenRouteTurnIndex = nil
        deliverWorkoutAlert(
            english: "Returning to start. Follow the route in reverse.",
            norwegian: "Vi løper tilbake til start. Følg ruten motsatt vei.",
            delivery: routeAlertConfiguration.delivery,
            haptic: .success,
            priority: .routeCritical
        )
    }

    func disableGhostDuringWorkout() {
        guard ghostRaceConfiguration != nil else { return }
        configureGhostRace(nil)
        guard let workoutSession, let startedAt,
              let payload = try? JSONEncoder().encode(
                ATHLTHGhostDisableDuringWorkout(
                    workoutStartedAt: startedAt,
                    requestedAt: Date()
                )
              ) else { return }
        Task { @MainActor in
            try? await workoutSession.sendToRemoteWorkoutSession(data: payload)
        }
    }

    func configurePlannedRoute(
        _ route: WatchRouteTransfer?
    ) {
        cachePlannedRouteGeometry(route)
        lastSpokenRouteTurnIndex = nil
        lastSpokenRouteTurnAt = nil

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
        if !configuration.enabled ||
            !configuration.shouldPreferIPhoneAudioWhenReachable ||
            !configuration.shouldUseAcknowledgedVoiceLease {
            iPhoneVoiceLease.reset()
        }

        if !configuration.enabled {
            audioCoachReadyAnnouncedForWorkout = false
            strengthRestCoachTask?.cancel()
            strengthRestCoachTask = nil
            strengthStatusCoachTask?.cancel()
            strengthStatusCoachTask = nil
            audioCoachActivationTask?.cancel()
            audioCoachActivationTask = nil
            speechSynthesizer.stopSpeaking(at: .immediate)
            coachCueQueue.reset()
            coachSpeechPaused = false
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
        let wasEnabled = audioCoachConfiguration.enabled
        let priorStatusInterval = wasEnabled
            ? audioCoachConfiguration.strengthStatusIntervalSeconds
            : nil

        publish {
            self.audioCoachConfiguration = configuration
        }

        resetAudioCoachThresholds()
        persistWorkoutRecoveryState()
        if !configuration.enabled ||
            !configuration.shouldPreferIPhoneAudioWhenReachable ||
            !configuration.shouldUseAcknowledgedVoiceLease {
            iPhoneVoiceLease.reset()
        }

        if !configuration.enabled {
            audioCoachReadyAnnouncedForWorkout = false
            strengthRestCoachTask?.cancel()
            strengthRestCoachTask = nil
            strengthStatusCoachTask?.cancel()
            strengthStatusCoachTask = nil
            speechSynthesizer.stopSpeaking(at: .immediate)
            coachCueQueue.reset()
            coachSpeechPaused = false
            deactivateAudioCoachAudioSession()
        } else {
            if !wasEnabled {
                audioCoachReadyAnnouncedForWorkout = false
            }
            if kind == .strength {
                let updatedInterval = configuration.strengthStatusIntervalSeconds
                if !wasEnabled || priorStatusInterval != updatedInterval {
                    strengthStatusCoachTask?.cancel()
                    strengthStatusCoachTask = nil
                    scheduleStrengthStatusCoach()
                }
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
            self.treadmillTargetPaceSecondsPerKilometer = nil
            self.structuredStepIndex = 0
            self.awaitingMainStart = false

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
        recordedStructuredRunSteps = []
        recordedStructuredRunMinutes = []
        lastIntervalProgressCueKey = nil
        lastIntervalWarningCueKey = nil
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

    /// Use the same HKWorkoutSession for a running interval added from the
    /// iPhone. Existing route, pulse, distance, completed steps and elapsed
    /// time are preserved. No second workout is started on Apple Watch.
    private func appendRunningPart(
        _ addition: WatchRunningWorkoutTransfer,
        startNow: Bool,
        commandID: UUID?,
        requestedWorkoutStart: Date?
    ) {
        guard kind == .running,
              isActive,
              let startedAt,
              let requestedWorkoutStart,
              abs(requestedWorkoutStart.timeIntervalSince(startedAt)) < 5 else {
            return
        }

        if let commandID, appliedRunningAppendCommands.contains(commandID) {
            return
        }

        let hasActivePart =
            structuredRunningWorkout != nil && !structuredWorkoutComplete
        guard ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: hasActivePart,
            startNow: startNow,
            steps: addition.steps
        ) else { return }

        let firstNewIndex = structuredRunningWorkout?.steps.count ?? 0
        if var existing = structuredRunningWorkout {
            existing.steps.append(contentsOf: addition.steps)
            existing.sourceWorkoutID = nil
            publish { self.structuredRunningWorkout = existing }
        } else {
            publish { self.structuredRunningWorkout = addition }
        }

        if !hasActivePart {
            structuredStepStartElapsedTime = elapsedTime
            structuredStepStartDistanceMeters = distanceMeters
            publish { self.structuredStepIndex = firstNewIndex }
        }
        structuredWorkoutComplete = false
        targetViolationStartedAt = nil
        lastTargetAlertAt = nil
        targetWasOutside = false

        if let commandID {
            if appliedRunningAppendCommands.count > 100 {
                appliedRunningAppendCommands.removeAll()
            }
            appliedRunningAppendCommands.insert(commandID)
        }
        persistWorkoutRecoveryState()
        if !hasActivePart {
            announceCurrentStructuredStep(prefix: "Starting")
        }
        Task { @MainActor [weak self] in
            await self?.sendLiveSnapshot(force: true)
        }
    }

    func setTreadmillTargetPaceSecondsPerKilometer(_ seconds: Double) {
        guard kind == .running,
              seconds.isFinite, (120...1200).contains(seconds) else { return }
        publish {
            self.treadmillTargetPaceSecondsPerKilometer =
                (seconds / 5).rounded() * 5
        }
        persistWorkoutRecoveryState()
        Task { @MainActor [weak self] in
            await self?.sendLiveSnapshot(force: true)
        }
    }

    func setTreadmillInclinePercent(
        _ percent: Double
    ) {
        guard treadmillInclinePercent != nil else {
            return
        }

        let value =
            min(
                max(
                    (percent * 2).rounded() / 2,
                    0
                ),
                20
            )

        publish {
            self.treadmillInclinePercent =
                value

            if var workout =
                    self.structuredRunningWorkout {
                workout.treadmillInclinePercent =
                    value
                self.structuredRunningWorkout =
                    workout
            }
        }

        persistWorkoutRecoveryState()

        Task { @MainActor [weak self] in
            await self?.sendLiveSnapshot(
                force: true
            )
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
            self.ghostRaceTitle =
                ghost?.opponentName ??
                ghost?.title
            self.ghostDistanceDeltaMeters = nil
            self.ghostTimeDeltaSeconds = nil
            self.ghostMapUserLatitude = nil
            self.ghostMapUserLongitude = nil
            self.ghostMapLatitude = nil
            self.ghostMapLongitude = nil
            self.ghostMapRevision = 0
            self.ghostComparisonUpdatedAt = nil
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
        ghostOvertakeTracker.reset()
        ghostFinalPhaseAnnounced = false
        lastLiveGhostConnectionText = nil
        lastGhostMapPublishedAt = nil
        ghostLastTrustedCourseMeters = nil
        ghostLastTrustedCourseElapsed = nil
        ghostOffRoute = false
        ghostReentryReliableSamples = 0
        ghostLastAnnouncedGapPercent = nil
        ghostLastGapAlertAt = nil
        lastRouteNavigationMapPublishedAt = nil

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
                    .importantLeadChangeMeters,
            statusDetailMode:
                context
                    .statusDetailModeRawValue
                    .flatMap(
                        GhostRaceStatusDetailMode
                            .init(rawValue:)
                    ),
            announceOvertakes:
                context
                    .announceOvertakes,
            finalPhaseEnabled:
                context
                    .finalPhaseEnabled,
            finalPhaseStartMeters:
                context
                    .finalPhaseStartMeters,
            liveConnectionAlerts:
                context
                    .liveConnectionAlerts
        )
    }

    // Location type is configured on the actual HealthKit session; .running
    // alone is not proof of an outdoor workout (e.g. treadmill sessions).
    var usesOutdoorGPS: Bool {
        switchedIndoorVenue == nil &&
            workoutSession?.workoutConfiguration.locationType == .outdoor
    }

    var averagePaceSecondsPerKilometer: TimeInterval? {
        ATHLTHRunningPace.average(
            elapsedSeconds: elapsedTime,
            distanceMeters: distanceMeters
        )
    }

    var currentStructuredStepElapsedTime: TimeInterval {
        if awaitingMainStart { return 0 }
        return max(
            elapsedTime -
            structuredStepStartElapsedTime,
            0
        )
    }

    var currentStructuredStepDistanceMeters: Double {
        if awaitingMainStart { return 0 }
        return max(
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

        coachSpeechPaused = false
        coachCueQueue.reset()
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

    /// Keep Watch workout capture and haptics active while iPhone AI speaks.
    /// A local timeout restores voice if the phone disconnects unexpectedly.
    func setAIConversationVoiceSuppressed(_ suppress: Bool) {
        if suppress {
            guard isActive, !aiConversationVoiceSuppressed else { return }
            aiConversationVoiceSuppressed = true
            coachSpeechWasPausedBeforeAI = coachSpeechPaused
            setCoachSpeechPaused(true)
            aiConversationVoiceTimeoutTask?.cancel()
            aiConversationVoiceTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(310))
                guard !Task.isCancelled else { return }
                self?.setAIConversationVoiceSuppressed(false)
            }
            return
        }

        guard aiConversationVoiceSuppressed else { return }
        aiConversationVoiceSuppressed = false
        aiConversationVoiceTimeoutTask?.cancel()
        aiConversationVoiceTimeoutTask = nil
        if !coachSpeechWasPausedBeforeAI, isActive {
            setCoachSpeechPaused(false)
        }
        coachSpeechWasPausedBeforeAI = false
    }

    /// Silences only the voice, not recording or haptic alerts.
    func setCoachSpeechPaused(_ paused: Bool) {
        if aiConversationVoiceSuppressed && !paused { return }
        guard audioCoachConfiguration.enabled, isActive else {
            coachSpeechPaused = false
            return
        }
        guard coachSpeechPaused != paused else { return }
        coachSpeechPaused = paused
        coachCueQueue.reset()
        guidancePriorityGate.reset()
        if paused {
            audioCoachActivationTask?.cancel()
            audioCoachActivationTask = nil
            speechSynthesizer.stopSpeaking(at: .immediate)
            deactivateAudioCoachAudioSession()
        }
    }

    /// A direct Watch tap should be spoken on the Watch, even when the
    /// paired iPhone normally owns automatic commentary.
    func announceCoachStatusNow() {
        guard audioCoachConfiguration.enabled,
              !coachSpeechPaused,
              isActive
        else { return }

        let summary: String
        if kind == .strength, let strengthSession {
            let english = ATHLTHStrengthCoachStatusMessage.make(
                completedSets: strengthSession.completedSets,
                totalSets: strengthSession.totalSets,
                exerciseName: strengthSession.exerciseName,
                restEndsAt: strengthSession.restEndsAt,
                norwegian: false
            )
            let norwegian = ATHLTHStrengthCoachStatusMessage.make(
                completedSets: strengthSession.completedSets,
                totalSets: strengthSession.totalSets,
                exerciseName: strengthSession.exerciseName,
                restEndsAt: strengthSession.restEndsAt,
                norwegian: true
            )
            summary = coachPhrase(
                english: english,
                norwegian: norwegian
            )
        } else {
            summary = metricsAnnouncement
        }
        let spoken = summary.isEmpty
            ? coachPhrase(
                english: "Workout is active.",
                norwegian: "Treningen er aktiv."
            )
            : summary
        speak(
            spoken,
            priority: .structuredStep,
            event: ATHLTHCoachEvent(
                kind: .manualStatus,
                key: UUID().uuidString,
                priority: .structuredStep,
                validFor: 8
            ),
            forceLocal: true
        )
    }

    /// Replay only the recent message spoken by this Watch. iPhone-owned
    /// commentary is deliberately not claimed as Watch audio history.
    func replayLastCoachMessage() {
        guard canReplayLastCoachMessage,
              let phrase = coachReplayMemory.replayableText()
        else { return }

        speak(
            phrase,
            priority: .structuredStep,
            forceLocal: true,
            rememberForReplay: false
        )
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

        guard ATHLTHStrengthWatchSnapshotAcceptance.shouldApply(
            incoming: snapshot, after: previous
        ) else { return }

        var accepted = snapshot
        if let pending = pendingStrengthWeight {
            if pending.workoutID != snapshot.workoutID {
                pendingStrengthWeight = nil
            } else if abs(snapshot.draftWeightKilograms - pending.value) < 0.001 {
                pendingStrengthWeight = nil
            } else if Date().timeIntervalSince(pending.changedAt) < 2.0 {
                // Do not replace a just-edited 60 kg with an older 57.5 kg
                // while connectivity delivers the intermediate snapshot.
                accepted.draftWeightKilograms = pending.value
            } else {
                pendingStrengthWeight = nil
            }
        }
        publish {
            self.strengthSession = accepted
            self.strengthActionPending = false
        }

        handleStrengthCoachTransition(
            from: previous,
            to: accepted
        )
        synchronizeHybridTreadmillSensors()
        persistWorkoutRecoveryState()
        if kind == .strength && mirroringActive {
            // Reflect iPhone-initiated exercise and rest changes immediately
            // on the lock screen rather than waiting for the next HR tick.
            Task { await sendLiveSnapshot(force: true) }
        }
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
           current.exerciseName != nil {
            let phrase =
                strengthNextExerciseCoachPhrase(
                    current
                )

            speak(
                coachPhrase(
                    english:
                        phrase.english,
                    norwegian:
                        phrase.norwegian
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

    private func strengthNextExerciseCoachPhrase(
        _ snapshot:
            WatchStrengthSessionSnapshot
    ) -> (
        english: String,
        norwegian: String
    ) {
        let name =
            snapshot.exerciseName ??
            snapshot.title

        var english = [
            "Next exercise. \(name)."
        ]
        var norwegian = [
            "Neste øvelse. \(name)."
        ]

        if audioCoachConfiguration
            .shouldAnnounceStrengthExerciseProgress,
           snapshot.exerciseCount > 0 {
            english.append(
                "Exercise \(snapshot.exerciseIndex + 1) of \(snapshot.exerciseCount)."
            )
            norwegian.append(
                "Øvelse \(snapshot.exerciseIndex + 1) av \(snapshot.exerciseCount)."
            )
        }

        if snapshot.setCount > 0 {
            english.append(
                "\(snapshot.setCount) sets."
            )
            norwegian.append(
                "\(snapshot.setCount) sett."
            )
        }

        let target =
            strengthSnapshotTargetPhrase(
                snapshot
            )

        if !target.english.isEmpty {
            english.append(
                "First target. \(target.english)"
            )
            norwegian.append(
                "Første mål. \(target.norwegian)"
            )
        }

        if snapshot.draftRestSeconds > 0 {
            english.append(
                "\(snapshot.draftRestSeconds) seconds rest."
            )
            norwegian.append(
                "\(snapshot.draftRestSeconds) sekunder hvile."
            )
        }

        return (
            english.joined(
                separator: " "
            ),
            norwegian.joined(
                separator: " "
            )
        )
    }

    private func strengthNextSetCoachPhrase(
        _ snapshot:
            WatchStrengthSessionSnapshot
    ) -> (
        english: String,
        norwegian: String
    )? {
        guard
            audioCoachConfiguration
                .shouldAnnounceStrengthNextSetDetails,
            !snapshot
                .currentExerciseComplete,
            snapshot.setCount > 0
        else {
            return nil
        }

        let number =
            snapshot.setNumber ??
            min(
                snapshot.setIndex + 1,
                snapshot.setCount
            )
        let target =
            strengthSnapshotTargetPhrase(
                snapshot
            )

        var english =
            "Next set. Set \(number) of \(snapshot.setCount)."
        var norwegian =
            "Neste sett. Sett \(number) av \(snapshot.setCount)."

        if !target.english.isEmpty {
            english +=
                " \(target.english)"
            norwegian +=
                " \(target.norwegian)"
        }

        return (
            english,
            norwegian
        )
    }

    private func upcomingStrengthExerciseCoachPhrase(
        _ snapshot:
            WatchStrengthSessionSnapshot
    ) -> (
        english: String,
        norwegian: String
    )? {
        guard
            snapshot.currentExerciseComplete,
            snapshot.hasNextExercise,
            let queue =
                snapshot.exerciseQueue,
            !queue.isEmpty
        else {
            return nil
        }

        // A spoken cue only needs the first pending index, not two
        // filtered and fully sorted copies of the exercise queue.
        let later = queue.lazy
            .filter {
                $0.index > snapshot.exerciseIndex &&
                $0.isCompleted != true
            }
            .min { $0.index < $1.index }
        let earlier = queue.lazy
            .filter {
                $0.index < snapshot.exerciseIndex &&
                $0.isCompleted != true
            }
            .min { $0.index < $1.index }

        guard let next =
                later ?? earlier
        else {
            return nil
        }

        var english =
            "Next exercise. \(next.name)."
        var norwegian =
            "Neste øvelse. \(next.name)."

        let pendingIndex =
            next.firstPendingSetIndex ??
            0

        if let plans =
                next.setPlans,
           plans.indices.contains(
                pendingIndex
           ) {
            let target =
                strengthSetPlanTargetPhrase(
                    plans[pendingIndex]
                )

            if !target.english.isEmpty {
                english +=
                    " \(target.english)"
                norwegian +=
                    " \(target.norwegian)"
            }
        }

        return (
            english,
            norwegian
        )
    }

    private func strengthSetPlanTargetPhrase(
        _ plan:
            WatchStrengthSetPlan
    ) -> (
        english: String,
        norwegian: String
    ) {
        var english = ""
        var norwegian = ""

        if let reps =
                plan.reps,
           reps > 0 {
            english =
                "\(reps) reps"
            norwegian =
                "\(reps) repetisjoner"
        } else if let seconds =
                    plan.durationSeconds,
                  seconds > 0 {
            let duration =
                strengthCoachDurationPhrase(
                    seconds
                )
            english =
                duration.english
            norwegian =
                duration.norwegian
        }

        if let level =
                plan.resistanceLevel,
           level > 0 {
            english +=
                english.isEmpty
                    ? "Resistance level \(level)"
                    : " at resistance level \(level)"
            norwegian +=
                norwegian.isEmpty
                    ? "Motstand \(level)"
                    : " på motstand \(level)"
        } else if let weight =
                    plan.weightKilograms,
                  weight > 0 {
            let formatted =
                weight.rounded() ==
                    weight
                    ? String(Int(weight))
                    : String(
                        format: "%.1f",
                        weight
                    )

            english +=
                english.isEmpty
                    ? "\(formatted) kilograms"
                    : " at \(formatted) kilograms"
            norwegian +=
                norwegian.isEmpty
                    ? "\(formatted) kilo"
                    : " på \(formatted) kilo"
        }

        if !english.isEmpty {
            english += "."
            norwegian += "."
        }

        return (
            english,
            norwegian
        )
    }

    private func strengthSnapshotTargetPhrase(
        _ snapshot:
            WatchStrengthSessionSnapshot
    ) -> (
        english: String,
        norwegian: String
    ) {
        var english = ""
        var norwegian = ""

        if snapshot.targetKindRaw ==
            "time",
           let seconds =
                snapshot
                    .draftDurationSeconds,
           seconds > 0 {
            let duration =
                strengthCoachDurationPhrase(
                    seconds
                )
            english =
                duration.english
            norwegian =
                duration.norwegian
        } else if snapshot.draftReps > 0 {
            english =
                "\(snapshot.draftReps) reps"
            norwegian =
                "\(snapshot.draftReps) repetisjoner"
        }

        if snapshot.loadKindRaw ==
            "resistanceLevel",
           let level =
                snapshot
                    .draftResistanceLevel,
           level > 0 {
            english +=
                english.isEmpty
                    ? "Resistance level \(level)"
                    : " at resistance level \(level)"
            norwegian +=
                norwegian.isEmpty
                    ? "Motstand \(level)"
                    : " på motstand \(level)"
        } else if snapshot
            .draftWeightKilograms > 0 {
            let weight =
                snapshot
                    .draftWeightKilograms
            let formatted =
                weight.rounded() ==
                    weight
                    ? String(Int(weight))
                    : String(
                        format: "%.1f",
                        weight
                    )

            english +=
                english.isEmpty
                    ? "\(formatted) kilograms"
                    : " at \(formatted) kilograms"
            norwegian +=
                norwegian.isEmpty
                    ? "\(formatted) kilo"
                    : " på \(formatted) kilo"
        }

        // These values are athlete-reported settings, not measured Watch
        // speed or a second running workout. Tell the user the source.
        if let speed = snapshot.manualTreadmillSpeedKilometersPerHour,
           speed.isFinite, speed > 0 {
            let speedText = String(format: "%.1f", speed)
            english += english.isEmpty ? "" : ". "
            norwegian += norwegian.isEmpty ? "" : ". "
            english += "Manually set speed \(speedText) kilometers per hour"
            norwegian += "Manuelt innstilt fart \(speedText) kilometer i timen"
            if let incline = snapshot.manualTreadmillInclinePercent,
               incline.isFinite, (0...20).contains(incline) {
                let inclineText = String(format: "%.1f", incline)
                english += ", incline \(inclineText) percent"
                norwegian += ", stigning \(inclineText) prosent"
            }
        }

        if !english.isEmpty {
            english += "."
            norwegian += "."
        }

        return (
            english,
            norwegian
        )
    }

    private func strengthCoachDurationPhrase(
        _ seconds: Int
    ) -> (
        english: String,
        norwegian: String
    ) {
        let bounded =
            max(seconds, 0)
        let minutes =
            bounded / 60
        let remainder =
            bounded % 60

        if minutes > 0,
           remainder > 0 {
            return (
                "\(minutes) minutes and \(remainder) seconds",
                "\(minutes) minutter og \(remainder) sekunder"
            )
        }

        if minutes > 0 {
            return (
                "\(minutes) minutes",
                "\(minutes) minutter"
            )
        }

        return (
            "\(remainder) seconds",
            "\(remainder) sekunder"
        )
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

                var englishParts:
                    [String] = []
                var norwegianParts:
                    [String] = []

                if self.audioCoachConfiguration
                    .shouldAnnounceStrengthRestComplete {
                    englishParts.append(
                        snapshot
                            .currentExerciseComplete
                            ? "Rest complete. Ready for the next exercise."
                            : "Rest complete."
                    )
                    norwegianParts.append(
                        snapshot
                            .currentExerciseComplete
                            ? "Hvilen er ferdig. Klar for neste øvelse."
                            : "Hvilen er ferdig."
                    )
                }

                if let currentSnapshot =
                        self.strengthSession {
                    if currentSnapshot
                        .currentExerciseComplete {
                        if self
                            .audioCoachConfiguration
                            .shouldAnnounceStrengthNextExercise,
                           let nextExercise =
                                self
                                    .upcomingStrengthExerciseCoachPhrase(
                                        currentSnapshot
                                    ) {
                            englishParts.append(
                                nextExercise
                                    .english
                            )
                            norwegianParts.append(
                                nextExercise
                                    .norwegian
                            )
                        }
                    } else if let nextSet =
                                self.strengthNextSetCoachPhrase(
                                    currentSnapshot
                                ) {
                        englishParts.append(
                            nextSet.english
                        )
                        norwegianParts.append(
                            nextSet.norwegian
                        )
                    }
                }

                if !englishParts.isEmpty {
                    self.speak(
                        self.coachPhrase(
                            english:
                                englishParts
                                    .joined(
                                        separator:
                                            " "
                                    ),
                            norwegian:
                                norwegianParts
                                    .joined(
                                        separator:
                                            " "
                                    )
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
                          self.audioCoachConfiguration.enabled,
                          self.audioCoachConfiguration.strengthStatusIntervalSeconds == interval,
                          let snapshot =
                            self.strengthSession
                    else {
                        return
                    }

                    let exercise =
                        snapshot.exerciseName ??
                        snapshot.title

                    var english =
                        "\(snapshot.completedSets) of \(snapshot.totalSets) sets complete. Current exercise: \(exercise)."
                    var norwegian =
                        "\(snapshot.completedSets) av \(snapshot.totalSets) sett fullført. Nåværende øvelse: \(exercise)."

                    if self.audioCoachConfiguration
                        .shouldAnnounceStrengthExerciseProgress,
                       snapshot.exerciseCount >
                        0 {
                        english +=
                            " Exercise \(snapshot.exerciseIndex + 1) of \(snapshot.exerciseCount)."
                        norwegian +=
                            " Øvelse \(snapshot.exerciseIndex + 1) av \(snapshot.exerciseCount)."
                    }

                    self.speak(
                        self.coachPhrase(
                            english: english,
                            norwegian:
                                norwegian
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
        let previousConnection =
            liveSurfaceContext
                .liveGhost?
                .connectionText

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

        let liveSignal = ATHLTHLiveGhostWatchSignal.resolve(
            context: liveGhost,
            isPaused: state == .paused || automaticPauseActive
        )
        publish {
            self.ghostRaceTitle =
                liveGhost.title
            // Keep the opponent's name while delayed, but never carry a
            // previous lead into the next audio cue or active Watch metric.
            self.ghostDistanceDeltaMeters =
                liveSignal.mayAnnouncePassing
                    ? liveGhost.distanceDeltaMeters : nil
            self.ghostTimeDeltaSeconds =
                liveSignal.mayAnnouncePassing
                    ? liveGhost.estimatedTimeDeltaSeconds : nil
        }

        let liveAudio =
            ghostAudioConfiguration(
                from: liveGhost.audio
            )
        if state == .running && !automaticPauseActive {
            announceLiveGhostConnectionChangeIfNeeded(
                previous: previousConnection,
            current:
                liveGhost.connectionText,
            opponentName:
                liveGhost.opponentName ??
                liveGhost.title,
                configuration: liveAudio
            )
        }

        guard isActive,
              state == .running,
              !automaticPauseActive,
              kind == .running,
              liveSignal.mayAnnouncePassing,
              let distanceDelta =
                    liveGhost
                        .distanceDeltaMeters
        else {
            return
        }

        evaluateGhostRaceCoach(
            configuration:
                liveAudio,
            userDistance:
                distanceMeters,
            distanceDelta:
                distanceDelta,
            timeDelta:
                liveGhost
                    .estimatedTimeDeltaSeconds
        )
    }

    /// A single strength HealthKit session keeps recording throughout hybrid
    /// phases. Enable extra *sample collection*, not a second workout, only
    /// during treadmill phases. Data are measured only when HealthKit actually
    /// supplies walking/running distance; a belt-speed target is never a sample.
    private func synchronizeHybridTreadmillSensors() {
        guard kind == .strength,
              let source = workoutBuilder?.dataSource,
              let distanceType = HKObjectType.quantityType(
                  forIdentifier: .distanceWalkingRunning
              ) else { return }
        let shouldCollect = strengthSession?.isEmbeddedRunningInterval == true
        guard shouldCollect != collectingHybridTreadmillDistance else { return }
        if shouldCollect {
            source.enableCollection(for: distanceType, predicate: nil)
        } else {
            source.disableCollection(for: distanceType)
        }
        collectingHybridTreadmillDistance = shouldCollect
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
            let next = min(max(durationSeconds, 0), 7_200)
            if snapshot.draftDurationSeconds != next {
                snapshot.timedSetCountdown = nil
            }
            snapshot.draftDurationSeconds = next
        }
        if let weightKilograms {
            let total = min(max(weightKilograms, 0), 999)
            snapshot.draftWeightKilograms = total
            pendingStrengthWeight = (
                workoutID: snapshot.workoutID,
                value: total,
                changedAt: Date()
            )
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

    /// Timed strength work uses a date anchor, not display tick counts.
    /// These operations are journaled like other set-scoped Watch actions.
    func startOrResumeTimedStrengthSet(allowIPhoneOnly: Bool = false) {
        guard var snapshot = strengthSession,
              (allowIPhoneOnly || snapshot.inputMode != .iPhone),
              snapshot.targetKindRaw == "time",
              !snapshot.isResting,
              !snapshot.currentExerciseComplete
        else { return }

        let now = Date()
        if var timer = snapshot.timedSetCountdown {
            guard !timer.isRunning, timer.remaining(at: now) > 0 else {
                return
            }
            timer.resumedAt = now
            snapshot.timedSetCountdown = timer
        } else {
            let seconds = min(max(snapshot.draftDurationSeconds ?? 60, 15), 7_200)
            snapshot.timedSetCountdown = WatchTimedStrengthCountdown(
                targetSeconds: seconds,
                secondsAtPause: TimeInterval(seconds),
                resumedAt: now
            )
        }

        guard sendTimedStrengthCommand(.startTimedSet, snapshot: snapshot, at: now)
        else { return }
        snapshot.updatedAt = now
        publish { self.strengthSession = snapshot }
        persistWorkoutRecoveryState()
    }

    func pauseTimedStrengthSet(allowIPhoneOnly: Bool = false) {
        guard var snapshot = strengthSession,
              (allowIPhoneOnly || snapshot.inputMode != .iPhone),
              var timer = snapshot.timedSetCountdown,
              timer.isRunning else { return }
        let now = Date()
        timer.secondsAtPause = timer.remaining(at: now)
        timer.resumedAt = nil
        snapshot.timedSetCountdown = timer

        guard sendTimedStrengthCommand(.pauseTimedSet, snapshot: snapshot, at: now)
        else { return }
        snapshot.updatedAt = now
        publish { self.strengthSession = snapshot }
        persistWorkoutRecoveryState()
    }

    func resetTimedStrengthSet() {
        guard var snapshot = strengthSession,
              snapshot.inputMode != .iPhone,
              snapshot.timedSetCountdown != nil else { return }
        let now = Date()
        snapshot.timedSetCountdown = nil

        guard sendTimedStrengthCommand(.resetTimedSet, snapshot: snapshot, at: now)
        else { return }
        snapshot.updatedAt = now
        publish { self.strengthSession = snapshot }
        persistWorkoutRecoveryState()
    }

    private func sendTimedStrengthCommand(
        _ kind: WatchStrengthCommandKind,
        snapshot: WatchStrengthSessionSnapshot,
        at date: Date
    ) -> Bool {
        sendStrengthCommand(
            WatchStrengthCommand(
                id: UUID(),
                workoutID: snapshot.workoutID,
                kind: kind,
                reps: nil,
                weightKilograms: nil,
                restSeconds: nil,
                addRestSeconds: nil,
                sentAt: date,
                exerciseIndex: snapshot.exerciseIndex,
                setIndex: snapshot.setIndex
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

        let completedAt = Date()
        let actualDuration = snapshot.targetKindRaw == "time"
            ? snapshot.timedSetCountdown.map {
                Int(min(max($0.elapsed(at: completedAt).rounded(), 0), 7_200))
            } ?? snapshot.draftDurationSeconds
            : snapshot.draftDurationSeconds
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
                    durationSeconds: actualDuration,
                    resistanceLevel:
                        snapshot
                            .draftResistanceLevel,
                    addRestSeconds: nil,
                    sentAt: completedAt,
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

        // Advance in one durable command when the final set is done.
        // Sending skipRest + nextExercise separately can cause the second
        // action to be missed while the companion processes the first.
        if snapshot.currentExerciseComplete &&
            snapshot.hasNextExercise {
            moveToNextStrengthExercise()
            return
        }

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

        updated.timedSetCountdown = nil

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
        guard let queue = snapshot.exerciseQueue else { return }
        let later = queue.first {
            $0.index > snapshot.exerciseIndex && $0.isCompleted != true
        }
        let earlier = queue.first {
            $0.index < snapshot.exerciseIndex && $0.isCompleted != true
        }
        guard let next = later ?? earlier
        else {
            publish {
                self.strengthActionPending =
                    false
            }
            return
        }

        var updated = snapshot
        updated.timedSetCountdown = nil
        updated.exerciseIndex =
            next.index
        updated.exerciseName =
            next.name
        updated.isEmbeddedRunningInterval = next.isEmbeddedRunningInterval
        updated.primaryMuscles =
            next.primaryMuscles
        updated.setIndex = next.firstPendingSetIndex ?? 0
        updated.setCount = next.setCount
        updated.setNumber = next.setCount > 0
            ? updated.setIndex + 1 : nil
        updated.currentExerciseComplete =
            next.setCount == 0
        updated.hasNextExercise =
            queue.contains { $0.index != next.index && $0.isCompleted != true }
        updated.allExercisesComplete =
            false
        applyStrengthPlanDefaults(
            to: &updated,
            exerciseIndex:
                next.index,
            setIndex: updated.setIndex
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
        snapshot.timedSetCountdown = nil
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
        snapshot.isEmbeddedRunningInterval = exercise.isEmbeddedRunningInterval
        snapshot.embeddedRunningPhaseTitle = plan.hybridPhaseTitle
        snapshot.embeddedRunningPhaseKind = plan.hybridPhaseKind
        snapshot.embeddedRunningTargetHeartRateZone = plan.hybridTargetHeartRateZone
        snapshot.embeddedRunningTargetPaceSecondsPerKilometer =
            plan.hybridTargetPaceSecondsPerKilometer

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

        if let targetRPE =
                plan.targetRPE {
            snapshot.draftRPE =
                min(
                    max(targetRPE, 1),
                    10
                )
        }

        if let targetRIR =
                plan.targetRIR {
            snapshot.draftRIR =
                min(
                    max(targetRIR, 0),
                    5
                )
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

    func configureCompanionWorkoutActivity(
        _ activity: WatchWorkoutActivityState
    ) {
        guard activity.updatedAt >=
                companionWorkoutActivity?
                    .updatedAt ??
                .distantPast
        else {
            return
        }

        companionWorkoutActivity =
            activity
    }

    func requestAIConversationOnIPhone() {
        guard isActive else { return }
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable
        else {
            errorMessage = ATHLTHLocalization.choose(
                english: "Open ATHLTH on iPhone to request an AI Coach conversation.",
                norwegian: "Åpne ATHLTH på iPhone for å be om en AI-samtale."
            )
            return
        }
        // No durable transferUserInfo. Stale requests never launch consent.
        WCSession.default.sendMessage([
            WatchTransferMetadataKey.kind:
                WatchTransferKind.aiCoachConversationRequest.rawValue,
            WatchTransferMetadataKey.sentAt:
                Date().timeIntervalSince1970
        ], replyHandler: nil, errorHandler: nil)
    }

    private func localWorkoutStartAllowed()
        async -> Bool {
        if companionWorkoutActivity?
            .isActive == true {
            errorMessage =
                ATHLTHLocalization.choose(
                    english:
                        "A workout is already running on iPhone. Finish it before starting another workout.",
                    norwegian:
                        "En økt kjører allerede på iPhone. Avslutt den før du starter en ny økt."
                )
            return false
        }

        guard WCSession.isSupported() else {
            return true
        }

        let session =
            WCSession.default

        guard
            session.activationState ==
                .activated,
            session.isReachable
        else {
            // Preserve standalone/offline Watch workouts. When the iPhone is
            // disconnected, use the last durable activity state we have.
            return companionWorkoutActivity?
                .isActive != true
        }

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind:
                WatchTransferKind
                    .workoutStartGuard
                    .rawValue,
            WatchTransferMetadataKey.sentAt:
                Date()
                    .timeIntervalSince1970
        ]

        let allowed: Bool? = await withCheckedContinuation {
            (continuation: CheckedContinuation<Bool?, Never>) in
            let completion = WatchStartGuardContinuation(continuation)

            session.sendMessage(
                payload,
                replyHandler: completion.makeReplyHandler(),
                errorHandler: completion.makeErrorHandler()
            )

            // If the iPhone stops replying, standalone Watch recording
            // must still be possible without indefinitely hanging START.
            Task {
                try? await Task.sleep(for: .seconds(3))
                completion.complete(nil)
            }
        }

        // Also check after the wait, as an iPhone session could have
        // become active while the connectivity request was pending.
        guard allowed != false,
              companionWorkoutActivity?.isActive != true
        else {
            errorMessage =
                ATHLTHLocalization.choose(
                    english:
                        "A workout is already running on iPhone. Finish it before starting another workout.",
                    norwegian:
                        "En økt kjører allerede på iPhone. Avslutt den før du starter en ny økt."
                )
            return false
        }

        return true
    }

    // Query actual HealthKit state before starting another workout.
    func currentWorkoutActivityForProbe() -> WatchWorkoutActivityState {
        let recording: Bool
        switch state {
        case .preparing, .running, .paused, .ending:
            recording = true
        case .idle, .completed, .failed:
            recording = false
        }
        let healthKitActive =
            workoutSession?.state == .running ||
            workoutSession?.state == .paused
        let active = recording || healthKitActive || recoveryInProgress
        return WatchWorkoutActivityState(
            isActive: active,
            title: active ? kind.title : nil,
            updatedAt: Date()
        )
    }

    func syncWorkoutActivityStateToPhone() {
        reportWorkoutActivityStateToPhone(
            state,
            force: true
        )
    }

    private func reportWorkoutActivityStateToPhone(
        _ workoutState: WatchWorkoutState,
        force: Bool = false
    ) {
        let active: Bool
        switch workoutState {
        case .preparing,
             .running,
             .paused,
             .ending:
            active = true
        case .idle,
             .completed,
             .failed:
            active = false
        }

        let activity =
            WatchWorkoutActivityState(
                isActive: active,
                title:
                    active
                        ? kind.title
                        : nil,
                updatedAt: Date()
            )

        if !force,
           let previous =
                lastReportedWorkoutActivity,
           previous.isActive ==
                activity.isActive,
           previous.title ==
                activity.title {
            return
        }

        lastReportedWorkoutActivity =
            activity

        guard
            WCSession.isSupported(),
            let data =
                try? JSONEncoder().encode(
                    activity
                )
        else {
            return
        }

        let session =
            WCSession.default

        guard session.activationState ==
                .activated
        else {
            return
        }

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind:
                WatchTransferKind
                    .workoutActivityState
                    .rawValue,
            WatchTransferMetadataKey.payload:
                data,
            WatchTransferMetadataKey.sentAt:
                activity.updatedAt
                    .timeIntervalSince1970
        ]

        session.transferUserInfo(
            payload
        )

        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: nil,
                errorHandler: nil
            )
        }
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
                reportWorkoutActivityStateToPhone(.idle, force: true)
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
            collectingHybridTreadmillDistance = false
            finishing = false
            kind = recoveredKind
            startedAt =
                recovered.startDate ??
                builder.startDate ??
                Date()

            restorePersistedWorkoutState(
                expectedKind: recoveredKind
            )
            synchronizeHybridTreadmillSensors()

            if usesOutdoorGPS,
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
                locationManager.stopUpdatingLocation()
                locationManager.allowsBackgroundLocationUpdates = false
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

            // A crash during finalization can restore an already-ended
            // HealthKit session. Resume its save sequence rather than leave
            // an indefinitely "ending" workout or lose its recorded data.
            if recovered.state == .ended {
                finishWorkout(at: recovered.endDate ?? Date())
            } else if recovered.state == .stopped {
                // .stopped is not .ended; end the recovered session so the
                // normal delegate can save the workout builder once.
                recovered.end()
            }

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
        route: WatchRouteTransfer? = nil,
        indoor: Bool? = nil
    ) async {
        guard await localWorkoutStartAllowed()
        else {
            return
        }

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
            indoor.map {
                $0 ? .indoor : .outdoor
            } ??
            (
                kind.usesOutdoorLocation
                    ? .outdoor
                    : .indoor
            )

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
                awaitingMainStart: awaitingMainStart,
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
                indoorVenue: switchedIndoorVenue,
                returningToRouteStart: returningToRouteStart,
                routeLegDistanceOffsetMeters: routeLegDistanceOffsetMeters,
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
        switchedIndoorVenue = snapshot.indoorVenue
        if let venue = snapshot.indoorVenue {
            indoorPromptedInThisWorkout = true
            indoorSuggestionAvailable = false
            automaticPauseEnabled = false
            treadmillInclinePercent = venue == .treadmill ? 0 : nil
        }
        ghostRaceConfiguration =
            snapshot.ghostRace
        returningToRouteStart = snapshot.returningToRouteStart ?? false
        routeLegDistanceOffsetMeters = max(
            0, snapshot.routeLegDistanceOffsetMeters ?? 0
        )
        strengthCommandJournal =
            snapshot.strengthCommands ?? []
        structuredStepStartElapsedTime =
            snapshot
                .structuredStepStartElapsedTime
        structuredStepStartDistanceMeters =
            snapshot
                .structuredStepStartDistanceMeters
        awaitingMainStart = snapshot.awaitingMainStart ?? false
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
        guard await localWorkoutStartAllowed()
        else {
            return
        }

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
        returningToRouteStart = false
        routeLegDistanceOffsetMeters = 0
        cachePlannedRouteGeometry(nil)

        publish {
            self.audioCoachConfiguration = .disabled
            self.structuredRunningWorkout = nil
            self.treadmillInclinePercent = nil
            self.treadmillTargetPaceSecondsPerKilometer = nil
            self.structuredStepIndex = 0
            self.plannedRoute = nil
            self.routeProgressPercent = nil
            self.routeRemainingMeters = nil
            self.routeDeviationMeters = nil
            self.routeDistanceToStartMeters = nil
            self.routeNavigationLatitude = nil
            self.routeNavigationLongitude = nil
            self.routeNavigationCourseDegrees = nil
            self.routeNavigationNearestPointIndex = nil
            self.routeNavigationRevision = 0
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
            self.ghostComparisonUpdatedAt = nil
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
        // A paused HealthKit recording must also freeze the current hybrid
        // treadmill interval. Journal the exact Watch event for offline replay.
        if strengthSession?.isEmbeddedRunningInterval == true,
           strengthSession?.timedSetCountdown?.isRunning == true {
            pauseTimedStrengthSet(allowIPhoneOnly: true)
        }
        manualPauseActive = true
        automaticPauseActive = false
        autoPauseDetector.reset(
            enabled: false
        )
        workoutSession?.pause()
    }

    func resume() {
        guard state == .paused else { return }
        // Resume the existing countdown, never start a new set or HKWorkout.
        if strengthSession?.isEmbeddedRunningInterval == true,
           let countdown = strengthSession?.timedSetCountdown,
           !countdown.isRunning,
           countdown.remaining() > 0 {
            startOrResumeTimedStrengthSet(allowIPhoneOnly: true)
        }
        manualPauseActive = false
        autoPauseDetector.reset(
            enabled: automaticPauseEnabled
        )
        workoutSession?.resume()
    }

    func end() {
        // Ignore repeated end taps while HealthKit is finishing the same
        // workout. Finishing and route persistence remain owned by the
        // existing session delegate and live workout builder.
        guard isActive, state != .ending, !finishing else { return }
        publishState(.ending)
        workoutSession?.end()
    }

    func reset() {
        setAIConversationVoiceSuppressed(false)
        stopTimer()
        workoutSession = nil
        workoutBuilder = nil
        collectingHybridTreadmillDistance = false
        routeBuilder = nil
        workoutLocation = nil
        workoutLocationMetadataAttached = false
        startedAt = nil
        resetIndoorProbeForNewWorkout()
        finishing = false
        mirroringActive = false
        mirroringRetryPending = false
        lastMirrorSnapshotSentAt = nil
        iPhoneVoiceLease.reset()
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
        ghostOvertakeTracker.reset()
        ghostFinalPhaseAnnounced = false
        lastLiveGhostConnectionText = nil
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
        coachHeartRateSampleAt = nil
        coachPaceSampleAt = nil
        speechSynthesizer.stopSpeaking(at: .immediate)
        deactivateAudioCoachAudioSession()
        audioCoachReadyAnnouncedForWorkout = false
        strengthCommandJournal = []
        guidancePriorityGate.reset()
        coachEventLedger.reset()
        coachCueQueue.reset()
        coachSpeechPaused = false
        coachReplayMemory.reset()
        lastCoachMessage = nil
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
            self.ghostComparisonUpdatedAt = nil
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
            self.treadmillTargetPaceSecondsPerKilometer = nil
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
        reportWorkoutActivityStateToPhone(.idle, force: true)
    }

    private func start(
        configuration: HKWorkoutConfiguration,
        kind: WatchWorkoutKind,
        route: WatchRouteTransfer?
    ) async {
        guard !isActive, state != .preparing, state != .ending else { return }

        let resolvedRoute = route ?? plannedRoute
        returningToRouteStart = false
        routeLegDistanceOffsetMeters = 0
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
            self.routeNavigationLatitude = nil
            self.routeNavigationLongitude = nil
            self.routeNavigationCourseDegrees = nil
            self.routeNavigationNearestPointIndex = nil
            self.routeNavigationRevision = 0
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
        resetIndoorProbeForNewWorkout()
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
        coachHeartRateSampleAt = nil
        coachPaceSampleAt = nil
        offRouteStartedAt = nil
        lastOffRouteAlertAt = nil
        routeWasOff = false
        targetViolationStartedAt = nil
        lastTargetAlertAt = nil
        targetWasOutside = false
        audioCoachReadyAnnouncedForWorkout = false
        guidancePriorityGate.reset()
        coachEventLedger.reset()
        coachCueQueue.reset()
        setAIConversationVoiceSuppressed(false)
        coachSpeechPaused = false
        coachReplayMemory.reset()
        lastCoachMessage = nil
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
            collectingHybridTreadmillDistance = false
            synchronizeHybridTreadmillSensors()
            finishing = false

            let startDate = Date()
            startedAt = startDate
            persistWorkoutRecoveryState()

            // Start the HealthKit session and collection before enabling
            // mirroring. Mirroring a session that is not yet active can
            // fail or leave the Watch launch in a bad lifecycle state.
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

            do {
                try await session.startMirroringToCompanionDevice()
                mirroringActive = true
                mirroringRetryPending = false
                await sendLiveSnapshot(
                    stateOverride: .preparing,
                    force: true
                )
            } catch {
                // Keep the workout running even when iPhone mirroring fails.
                mirroringActive = false
                mirroringRetryPending = true
            }

            if configuration.locationType != .outdoor {
                locationManager.stopUpdatingLocation()
                locationManager.allowsBackgroundLocationUpdates = false
            } else {
                locationManager.requestWhenInUseAuthorization()
            }

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

    /// Watch-owned clock for embedded treadmill phases. The phone can be
    /// locked or out of range: durable Watch commands replay each completion
    /// into the original strength workout without creating another recording.
    private func advanceEmbeddedHybridIntervalIfNeeded(at date: Date) {
        guard ATHLTHHybridWatchIntervalPolicy.shouldAutoAdvance(
            strengthSession,
            workoutState: mirrorState(for: state),
            at: date
        ),
        let before = strengthSession,
        let watchStartedAt = startedAt,
        let plannedStartedAt = before.startedAt,
        abs(watchStartedAt.timeIntervalSince(plannedStartedAt)) <= 180
        else { return }

        completeStrengthSet()
        guard let after = strengthSession,
              after.workoutID == before.workoutID,
              after.exerciseIndex == before.exerciseIndex,
              after.setIndex > before.setIndex,
              after.isEmbeddedRunningInterval == true,
              after.targetKindRaw == "time",
              !after.isResting,
              !after.currentExerciseComplete
        else { return }
        startOrResumeTimedStrengthSet()
    }

    private func resetIndoorProbeForNewWorkout() {
        indoorSuggestionAvailable = false
        switchedIndoorVenue = nil
        indoorPromptedInThisWorkout = false
        indoorFirstFix = nil
        indoorLastFix = nil
        indoorFixCount = 0
        indoorProbeDistanceMeters = 0
        indoorPreviousReliableLocation = nil
    }

    private func collectIndoorProbe(_ location: CLLocation) {
        guard switchedIndoorVenue == nil, location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 30,
              abs(location.timestamp.timeIntervalSinceNow) < 15 else { return }
        if indoorFirstFix == nil { indoorFirstFix = location.timestamp }
        indoorLastFix = location.timestamp
        indoorFixCount += 1
        if let previous = indoorPreviousReliableLocation {
            let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
            if seconds > 0, seconds <= 30 {
                let metres = location.distance(from: previous)
                if metres.isFinite, metres >= 0, metres / seconds <= 12 {
                    indoorProbeDistanceMeters += metres
                }
            }
        }
        indoorPreviousReliableLocation = location
    }

    private func evaluateIndoorSuggestion(now: Date) {
        guard kind == .running, let startedAt else { return }
        guard ATHLTHIndoorRunDetection.shouldOffer(
            elapsedWallSeconds: now.timeIntervalSince(startedAt),
            acceptedDistanceMeters: indoorProbeDistanceMeters,
            firstReliableFix: indoorFirstFix,
            lastReliableFix: indoorLastFix,
            acceptedFixCount: indoorFixCount,
            now: now,
            isOutdoor: usesOutdoorGPS,
            manualPause: manualPauseActive,
            hasPlannedRouteOrGhost: plannedRoute != nil ||
                ghostRaceConfiguration != nil,
            alreadyPrompted: indoorPromptedInThisWorkout
        ) else { return }
        indoorPromptedInThisWorkout = true
        indoorSuggestionAvailable = true
        WKInterfaceDevice.current().play(.notification)
    }

    func dismissIndoorSuggestion() {
        indoorSuggestionAvailable = false
        indoorPromptedInThisWorkout = true
    }

    /// Start a new *activity* with indoor sensors inside the existing HealthKit
    /// workout. Do not create a second session, reset intervals, or fake speed.
    @discardableResult
    func switchToIndoorRunning(_ venue: ATHLTHIndoorRunVenue) -> Bool {
        guard kind == .running,
              let session = workoutSession,
              state == .running || automaticPauseActive,
              !manualPauseActive else { return false }
        if switchedIndoorVenue != nil {
            switchedIndoorVenue = venue
            indoorSuggestionAvailable = false
            return true
        }
        let indoor = HKWorkoutConfiguration()
        indoor.activityType = .running
        indoor.locationType = .indoor
        if automaticPauseActive {
            automaticPauseActive = false
            session.resume()
        }
        session.beginNewActivity(
            configuration: indoor,
            date: Date(),
            metadata: ["ATHLTHIndoorVenue": venue.rawValue,
                       "ATHLTHDetectedFromStationaryGPS": true]
        )
        switchedIndoorVenue = venue
        indoorSuggestionAvailable = false
        indoorPromptedInThisWorkout = true
        automaticPauseEnabled = false
        autoPauseDetector.reset(enabled: false)
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        lastAcceptedOutdoorLocation = nil
        lastRenderedRouteLocation = nil
        treadmillInclinePercent = venue == .treadmill ? 0 : nil
        treadmillTargetPaceSecondsPerKilometer = nil
        routeProgressPercent = nil
        routeRemainingMeters = nil
        routeDeviationMeters = nil
        routeNavigationLatitude = nil
        routeNavigationLongitude = nil
        routeNavigationCourseDegrees = nil
        disableGhostDuringWorkout()
        configurePlannedRoute(nil)
        returningToRouteStart = false
        persistWorkoutRecoveryState()
        return true
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

                self.evaluateIndoorSuggestion(now: Date())
                self.recordRunningMinuteIfDue()
                self.advanceEmbeddedHybridIntervalIfNeeded(at: Date())
                self.evaluateStructuredRunningWorkout()
                self.evaluateWorkoutTargetAlerts()
                self.evaluateFuelAudioCoach()
                self.evaluateAudioCoach()
                await self.sendLiveSnapshot()
            }
        }
    }

    private func resetAudioCoachThresholds() {
        lastGoalEncouragementAt = nil
        smartCoachState.reset()
        let configuration = audioCoachConfiguration
        customAudioCoachLastSlots = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: configuration.customRules ?? [],
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedTime
        )
        nextFuelAnnouncementSeconds = ATHLTHFuelVoicePrompt.nextDue(
            after: elapsedTime,
            config: configuration
        )

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
            priority: .routineCoach,
            event: ATHLTHCoachEvent(
                kind: .workoutStart,
                key: "ready",
                priority: .routineCoach,
                validFor: 15
            )
        )
    }

    private func evaluateFuelAudioCoach() {
        guard state == .running,
              audioCoachConfiguration.enabled,
              !coachSpeechPaused,
              let next = nextFuelAnnouncementSeconds,
              elapsedTime >= next
        else { return }

        let config = audioCoachConfiguration
        // Advance based on elapsed workout time, never wall clock time.
        // If a watch/phone reconnect misses a slot, skip stale prompts.
        nextFuelAnnouncementSeconds = ATHLTHFuelVoicePrompt.nextDue(
            after: elapsedTime,
            config: config
        )

        // Never catch up an overdue cue after a long pause or reconnect.
        guard ATHLTHFuelVoicePrompt.isFreshDue(
            elapsed: elapsedTime,
            scheduled: next
        ),
        let phrase = ATHLTHFuelVoicePrompt.phrase(config: config)
        else { return }

        speak(
            phrase,
            priority: .routineCoach,
            event: ATHLTHCoachEvent(
                kind: .routineMilestone,
                key: "fuel:\(Int(next))",
                priority: .routineCoach,
                validFor: 12
            )
        )
    }

    private func evaluateCustomAudioCoachRules() {
        guard !coachSpeechPaused, kind == .running || kind == .walking else {
            return
        }
        let messages = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: audioCoachConfiguration.customRules ?? [],
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedTime,
            paceSecondsPerKilometer: currentPaceSecondsPerKilometer,
            heartRateBPM: hasFreshHeartRate ? heartRate : nil,
            norwegian: coachPhrase(english: "en", norwegian: "no") == "no",
            lastSlots: &customAudioCoachLastSlots
        )
        guard !messages.isEmpty else { return }
        speak(
            messages.joined(separator: ". "),
            priority: .routineCoach,
            event: ATHLTHCoachEvent(
                kind: .routineMilestone,
                key: "custom:\(Int(elapsedTime)):\(Int(distanceMeters))",
                priority: .routineCoach,
                validFor: 10
            )
        )
    }

    private func evaluateSmartAudioCoach() {
        guard !coachSpeechPaused,
              kind == .running || kind == .walking,
              let settings = audioCoachConfiguration.smartPrompts
        else { return }
        let norwegian = coachPhrase(english: "en", norwegian: "no") == "no"
        if usesOutdoorGPS, let location = lastAcceptedOutdoorLocation,
           let message = smartCoachState.nextLandmark(
               settings: settings,
               latitude: location.coordinate.latitude,
               longitude: location.coordinate.longitude,
               horizontalAccuracy: location.horizontalAccuracy,
               locationAge: Date().timeIntervalSince(location.timestamp),
               norwegian: norwegian
           ) {
            speak(
                message,
                priority: .routineCoach,
                event: ATHLTHCoachEvent(
                    kind: .routineMilestone,
                    key: "smart-place:\(Int(elapsedTime))",
                    priority: .routineCoach,
                    validFor: 12
                )
            )
            return
        }

        if let message = smartCoachState.nextMotivation(
            settings: settings,
            elapsed: elapsedTime,
            paceSecondsPerKilometer: currentPaceSecondsPerKilometer,
            norwegian: norwegian
        ) {
            speak(
                message,
                priority: .routineCoach,
                event: ATHLTHCoachEvent(
                    kind: .routineMilestone,
                    key: "smart-motivation:\(Int(elapsedTime))",
                    priority: .routineCoach,
                    validFor: 12
                )
            )
        }
    }

    private func evaluateAudioCoach() {
        guard state == .running,
              audioCoachConfiguration.enabled
        else {
            return
        }

        evaluateCustomAudioCoachRules()
        evaluateSmartAudioCoach()

        var shouldAnnounce = false
        var milestoneKeys: [String] = []

        if let interval =
                audioCoachConfiguration.distanceIntervalMeters,
           interval > 0,
           let nextDistance = nextDistanceAnnouncementMeters,
           distanceMeters >= nextDistance {
            milestoneKeys.append("d\(Int(nextDistance.rounded()))")
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
            milestoneKeys.append("t\(Int(nextTime.rounded()))")
            repeat {
                nextTimeAnnouncementSeconds =
                    (nextTimeAnnouncementSeconds ?? nextTime) +
                    interval
            } while elapsedTime >=
                (nextTimeAnnouncementSeconds ?? .greatestFiniteMagnitude)

            shouldAnnounce = true
        }

        if shouldAnnounce {
            guard ATHLTHCoachRoutineContextPolicy.shouldSpeakMilestone(
                step: currentStructuredRunningStep,
                elapsedInStep: currentStructuredStepElapsedTime,
                distanceInStepMeters: currentStructuredStepDistanceMeters
            ) else { return }

            var message = metricsAnnouncement
            guard !message.isEmpty else { return }

            if let feedback = ATHLTHCoachGoalEncouragement.phrase(
                style: audioCoachConfiguration.speechStyle ?? .balanced,
                step: currentStructuredRunningStep,
                paceSecondsPerKilometer: currentPaceSecondsPerKilometer,
                paceSampleAt: coachPaceSampleAt,
                elapsedInStep: currentStructuredStepElapsedTime,
                lastSpokenAt: lastGoalEncouragementAt,
                norwegian: coachPhrase(english: "en", norwegian: "no") == "no"
            ) {
                message += ". " + feedback
                lastGoalEncouragementAt = Date()
            }

            WKInterfaceDevice.current().play(.click)
            speak(
                message,
                priority: .routineCoach,
                event: ATHLTHCoachEvent(
                    kind: .routineMilestone,
                    key: milestoneKeys.joined(separator: "-"),
                    priority: .routineCoach,
                    validFor: 10
                )
            )
        }
    }

    /// Sample once per 60 seconds of active step time, plus any residual
    /// seconds when the user advances. Do not substitute target speed for
    /// measured Watch distance or mark manually set incline as measured.
    /// Sample actual Watch distance and time for ordinary treadmill sessions,
    /// including those without a structured interval workout.
    private func recordRunningMinuteIfDue(force: Bool = false) {
        guard state == .running,
              kind == .running || kind == .walking,
              !awaitingMainStart else { return }

        let step = currentStructuredRunningStep
        let index = step == nil ? -1 : structuredStepIndex
        let history = recordedStructuredRunMinutes.filter { $0.stepIndex == index }
        let previousEnd = history.last?.stepElapsedAtEndSeconds ?? 0
        let currentEnd = step == nil ? elapsedTime : currentStructuredStepElapsedTime
        let seconds = max(currentEnd - previousEnd, 0)
        guard (force && seconds >= 2) || (!force && seconds >= 60)
        else { return }
        let previouslyMeasured = history.reduce(0.0) { $0 + $1.recordedDistanceMeters }
        let measuredDistance = step == nil ? distanceMeters : currentStructuredStepDistanceMeters
        let newMeters = max(measuredDistance - previouslyMeasured, 0)
        recordedStructuredRunMinutes.append(ATHLTHRecordedRunningMinute(
            stepIndex: index,
            stepElapsedAtEndSeconds: currentEnd,
            activeSeconds: seconds,
            recordedDistanceMeters: newMeters,
            watchHeartRateBPM: hasFreshHeartRate ? heartRate : nil,
            targetPaceSecondsPerKilometer: step?.targetPaceMinSecondsPerKilometer,
            targetTreadmillInclinePercent: step?.targetTreadmillInclinePercent,
            manuallyEnteredTreadmillInclinePercent: treadmillInclinePercent
        ))
    }

    private func evaluateStructuredRunningWorkout() {
        guard state == .running,
              !awaitingMainStart,
              (kind == .running || kind == .walking),
              !structuredWorkoutComplete,
              let step = currentStructuredRunningStep
        else {
            return
        }

        announceIntervalProgressIfDue(for: step)

        // Warm-up and cool-down are minimum suggested times, never auto-advance.
        // The runner explicitly chooses when the actual main set begins or ends.
        if step.phase == "cooldown" ||
           (step.phase == "warmup" &&
            structuredRunningWorkout?.autoStartMainAfterWarmup != true) { return }
        if step.measure == .time,
           step.phase != "warmup",
           structuredRunningWorkout?.autoAdvanceTimedSteps == false {
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

    private func announceIntervalProgressIfDue(for step: WatchRunningWorkoutStep) {
        guard audioCoachConfiguration.enabled,
              !coachSpeechPaused,
              let configuration = structuredRunningWorkout,
              step.measure == .time,
              let total = step.durationSeconds,
              total > 0 else { return }

        let elapsed = currentStructuredStepElapsedTime
        let remaining = max(total - elapsed, 0)
        let norwegian = coachPhrase(english: "en", norwegian: "no") == "no"

        if let lead = configuration.intervalCoachCountdownSeconds,
           lead >= 5, lead < total,
           remaining > 0, remaining <= lead,
           remaining > lead - 2.5 {
            let key = "\(structuredStepIndex):\(Int(lead))"
            if lastIntervalWarningCueKey != key {
                lastIntervalWarningCueKey = key
                speak(
                    norwegian ? "\(Int(remaining.rounded())) sekunder igjen av \(step.title)"
                              : "\(Int(remaining.rounded())) seconds left in \(step.title)",
                    priority: .structuredStep,
                    event: ATHLTHCoachEvent(
                        kind: .runningStep, key: "warning:\(key)",
                        priority: .structuredStep, validFor: 8
                    )
                )
            }
            return
        }

        guard let interval = configuration.intervalCoachCueEverySeconds,
              interval >= 15, interval.isFinite,
              elapsed >= interval else { return }
        let slot = Int(floor(elapsed / interval))
        let dueTime = Double(slot) * interval
        guard slot > 0, elapsed - dueTime < 2.5, remaining > 2 else { return }
        let key = "\(structuredStepIndex):\(slot)"
        guard lastIntervalProgressCueKey != key else { return }
        lastIntervalProgressCueKey = key
        speak(
            norwegian ? "\(Int(remaining.rounded())) sekunder igjen av \(step.title)"
                      : "\(Int(remaining.rounded())) seconds remaining in \(step.title)",
            priority: .routineCoach,
            event: ATHLTHCoachEvent(
                kind: .routineMilestone, key: "interval:\(key)",
                priority: .routineCoach, validFor: 8
            )
        )
    }

    /// One action for the runner, but two deliberate steps at the warm-up boundary.
    func advanceStructuredRunningWorkoutManually() {
        guard state == .running,
              currentStructuredRunningStep != nil,
              !structuredWorkoutComplete else { return }
        if awaitingMainStart {
            startStructuredMainAfterWarmup()
            return
        }
        guard let current = currentStructuredRunningStep,
              current.phase == "warmup" ||
              current.phase == "cooldown" ||
              current.measure == .open ||
              structuredRunningWorkout?.autoAdvanceTimedSteps == false else {
            // Prevent a double tap on Start main from skipping effort one.
            return
        }
        advanceStructuredRunningWorkout(manually: true)
    }

    private func startStructuredMainAfterWarmup() {
        guard state == .running, awaitingMainStart,
              currentStructuredRunningStep != nil else { return }
        // Discard distance/time while waiting; it never becomes a work interval.
        structuredStepStartElapsedTime = elapsedTime
        structuredStepStartDistanceMeters = distanceMeters
        lastIntervalProgressCueKey = nil
        lastIntervalWarningCueKey = nil
        if structuredRunningWorkout?.deferRouteUntilMain == true,
           structuredStepIndex == 1 {
            routeLegDistanceOffsetMeters = distanceMeters
        }
        publish { self.awaitingMainStart = false }
        persistWorkoutRecoveryState()
        WKInterfaceDevice.current().play(.start)
        announceCurrentStructuredStep(prefix: "Starting")
    }

    private func advanceStructuredRunningWorkout(manually: Bool = false) {
        guard let workout = structuredRunningWorkout else {
            return
        }

        let finishedIndex = structuredStepIndex
        let finishedStep = workout.steps.indices.contains(finishedIndex)
            ? workout.steps[finishedIndex] : nil
        // Book the precise scheduled end for automatic timed steps.
        let endElapsed: TimeInterval = {
            if !manually, finishedStep?.measure == .time,
               let seconds = finishedStep?.durationSeconds, seconds > 0 {
                return structuredStepStartElapsedTime + seconds
            }
            return elapsedTime
        }()
        recordRunningMinuteIfDue(force: true)
        let seconds = max(0, endElapsed - structuredStepStartElapsedTime)
        let meters = distanceMeters - structuredStepStartDistanceMeters
        if seconds >= 0, meters >= 0,
           workout.steps.indices.contains(finishedIndex),
           !recordedStructuredRunSteps.contains(where: { $0.index == finishedIndex }) {
            let finishedStep = workout.steps[finishedIndex]
            recordedStructuredRunSteps.append(ATHLTHRecordedRunningStep(
                index: finishedIndex,
                title: finishedStep.title,
                phase: finishedStep.phase,
                activeSeconds: seconds,
                distanceMeters: meters,
                isUserReported: false,
                targetPaceSecondsPerKilometer:
                    finishedStep.targetPaceMinSecondsPerKilometer,
                targetDurationSeconds: finishedStep.durationSeconds,
                targetHeartRateZone: finishedStep.targetHeartRateZone,
                targetTreadmillInclinePercent:
                    finishedStep.targetTreadmillInclinePercent
            ))
        }

        let nextIndex = finishedIndex + 1

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

        structuredStepStartElapsedTime = endElapsed
        structuredStepStartDistanceMeters = distanceMeters

        targetViolationStartedAt = nil
        lastTargetAlertAt = nil
        targetWasOutside = false

        let mustStartMainManually = finishedStep?.phase == "warmup" &&
            workout.autoStartMainAfterWarmup != true &&
            !(manually && workout.deferRouteUntilMain == true)
        if finishedStep?.phase == "warmup",
           workout.deferRouteUntilMain == true {
            routeLegDistanceOffsetMeters = distanceMeters
        }
        publish {
            self.structuredStepIndex = nextIndex
            self.awaitingMainStart = mustStartMainManually
            self.liveTargetStatus = nil
        }

        persistWorkoutRecoveryState()
        WKInterfaceDevice.current().play(.notification)
        if mustStartMainManually {
            if audioCoachConfiguration.enabled {
                speak(
                    coachPhrase(
                        english: "Warm-up finished. Start the main section when ready.",
                        norwegian: "Oppvarming avsluttet. Start hoveddelen når du er klar."
                    ), priority: .structuredStep
                )
            }
        } else {
            announceCurrentStructuredStep(prefix: "Next")
        }
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

        let position: ATHLTHCoachStructuredStepSpeech.Position
        switch prefix {
        case "Starting": position = .starting
        case "Next": position = .next
        default: position = .current
        }

        let norwegian = coachPhrase(
            english: "en", norwegian: "no"
        ) == "no"
        speak(
            ATHLTHIntervalCoachCue.appendToStepAnnouncement(
                ATHLTHCoachStructuredStepSpeech.phrase(
                    for: step,
                    position: position,
                    norwegian: norwegian
                ),
                step: step,
                norwegian: norwegian
            ),
            priority: .structuredStep,
            event: ATHLTHCoachEvent(
                kind: .runningStep,
                // Shared with the mirrored iPhone cue key for this step.
                key: String(structuredStepIndex),
                priority: .structuredStep,
                validFor: 15
            )
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
           ATHLTHCoachSensorFreshness.validHeartRate(
               heartRate,
               sampledAt: coachHeartRateSampleAt
           ) {
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

        if let step = currentStructuredRunningStep,
           let remaining = ATHLTHCoachStructuredStepSpeech.remainingSummary(
                for: step,
                elapsedInStep: currentStructuredStepElapsedTime,
                distanceInStepMeters: currentStructuredStepDistanceMeters,
                announceTime: configuration.announceRemainingStepTime,
                announceDistance: configuration.announceRemainingStepDistance,
                norwegian: coachPhrase(english: "en", norwegian: "no") == "no"
           ) {
            parts.append(remaining)
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
        guard (kind == .running || kind == .walking),
              usesOutdoorGPS,
              ATHLTHCoachSensorFreshness.isFresh(
                  sampledAt: location.timestamp,
                  maximumAge: ATHLTHCoachSensorFreshness.maximumPaceAge
              )
        else {
            return
        }

        if let rawPace = ATHLTHRunningPace.outdoorGPS(
            speedMetersPerSecond: location.speed,
            isOutdoor: usesOutdoorGPS
        ) {
            let smoothed: TimeInterval
            if let existing = currentPaceSecondsPerKilometer {
                smoothed = existing * 0.72 + rawPace * 0.28
            } else {
                smoothed = rawPace
            }
            coachPaceSampleAt = location.timestamp
            publish {
                self.currentPaceSecondsPerKilometer = smoothed
            }
        }

        updateRouteNavigation(
            using: location
        )
    }

    private func updateRouteNavigation(
        using location: CLLocation
    ) {
        if structuredRunningWorkout?.deferRouteUntilMain == true,
           structuredStepIndex == 0 || awaitingMainStart {
            return
        }
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
                        },
                    workoutDistanceMeters: max(
                        distanceMeters - routeLegDistanceOffsetMeters, 0
                    ),
                    previousRouteMeters: routeProgressPercent.map {
                        $0 / 100 * plannedRouteGeometryMeters
                    },
                    courseAnchorMeters: ghostRaceConfiguration != nil
                        ? (ghostLastTrustedCourseMeters ?? 0) : nil,
                    secondsSinceCourseAnchor: ghostRaceConfiguration != nil
                        ? max(elapsedTime - (ghostLastTrustedCourseElapsed ?? 0), 0)
                        : nil
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

        publishRouteNavigationPositionIfNeeded(
            location:
                location,
            nearestPointIndex:
                guidance
                    .nearestRoutePointIndex
        )

        updateGhostRace(
            traveledAlongRoute:
                guidance.traveledAlongRouteMeters,
            deviationMeters:
                guidance.deviationMeters,
            userLocation:
                location
        )

        evaluateRouteAlert(
            deviationMeters:
                guidance.deviationMeters,
            horizontalAccuracy:
                location.horizontalAccuracy
        )
        evaluateUpcomingRouteTurn(
            location: location,
            nearestIndex: guidance.nearestRoutePointIndex,
            deviationMeters: guidance.deviationMeters
        )
    }

    private func publishRouteNavigationPositionIfNeeded(
        location: CLLocation,
        nearestPointIndex: Int
    ) {
        guard plannedRoute != nil
        else {
            return
        }

        let now = Date()
        if let lastRouteNavigationMapPublishedAt,
           now.timeIntervalSince(
                lastRouteNavigationMapPublishedAt
           ) < 0.85 {
            return
        }

        lastRouteNavigationMapPublishedAt = now

        let resolvedCourse =
            location.course >= 0 &&
            location.course <= 360
                ? location.course
                : nil

        publish {
            self.routeNavigationLatitude =
                location.coordinate.latitude
            self.routeNavigationLongitude =
                location.coordinate.longitude
            self.routeNavigationCourseDegrees =
                resolvedCourse
            self.routeNavigationNearestPointIndex =
                nearestPointIndex
            self.routeNavigationRevision &+= 1
        }
    }

    private func updateGhostRace(
        traveledAlongRoute: Double,
        deviationMeters: Double,
        userLocation: CLLocation
    ) {
        guard let ghost = ghostRaceConfiguration,
              ghost.points.count >= 2,
              ghost.routeDistanceMeters > 0 else { return }

        let points = ghost.points
        let targetTime = max(elapsedTime, 0)
        // Crucial: Ghost runs on its own fixed course clock. Its location
        // keeps moving even while the athlete is off the planned route.
        guard let ghostAtTime = ATHLTHGhostTimeline.interpolate(
            at: targetTime,
            count: points.count,
            position: { points[$0].elapsedTime },
            value: { points[$0].cumulativeMeters }
        ), ghostAtTime.isFinite else { return }

        if userLocation.horizontalAccuracy >= 0 &&
            userLocation.horizontalAccuracy <= 65 {
            publishGhostMapPositionIfNeeded(
                userLocation: userLocation,
                ghostDistanceMeters: ghostAtTime,
                routeDistanceMeters: ghost.routeDistanceMeters
            )
        }

        let reliable = ATHLTHGhostCourseProgressPolicy.isReliableOnRoute(
            horizontalAccuracy: userLocation.horizontalAccuracy,
            deviationMeters: deviationMeters,
            alertThresholdMeters: routeAlertConfiguration.deviationMeters
        )

        if !reliable {
            ghostOffRoute = true
            ghostReentryReliableSamples = 0
            ghostOvertakeTracker.invalidatePending()
            publish {
                self.ghostDistanceDeltaMeters = nil
                self.ghostTimeDeltaSeconds = nil
                self.ghostComparisonUpdatedAt = nil
            }
            return
        }

        // Two good fixes are required before comparing again after an
        // excursion. No status is announced on the first GPS snap-back.
        if ghostOffRoute {
            ghostReentryReliableSamples += 1
            if ghostReentryReliableSamples < 2 {
                ghostOvertakeTracker.invalidatePending()
                return
            }
            ghostOffRoute = false
            ghostReentryReliableSamples = 0
        }

        let userDistance = min(max(traveledAlongRoute, 0),
                               ghost.routeDistanceMeters)
        guard ATHLTHGhostCourseProgressPolicy.plausibleCourseAdvance(
            previousMeters: ghostLastTrustedCourseMeters,
            previousElapsed: ghostLastTrustedCourseElapsed,
            candidateMeters: userDistance,
            elapsed: elapsedTime
        ) else {
            ghostOvertakeTracker.invalidatePending()
            publish {
                self.ghostDistanceDeltaMeters = nil
                self.ghostTimeDeltaSeconds = nil
                self.ghostComparisonUpdatedAt = nil
            }
            return
        }

        let ghostAtDistance = ATHLTHGhostTimeline.interpolate(
            at: userDistance,
            count: points.count,
            position: { points[$0].cumulativeMeters },
            value: { points[$0].elapsedTime }
        )
        guard let ghostAtDistance, ghostAtDistance.isFinite else { return }
        ghostLastTrustedCourseMeters = max(
            ghostLastTrustedCourseMeters ?? 0, userDistance
        )
        ghostLastTrustedCourseElapsed = elapsedTime

        // Off-course extra kilometres cost elapsed time. They never advance
        // own course progress or drag the Ghost icon toward the runner.
        let distanceDelta = userDistance - ghostAtTime
        let timeDelta = ghostAtDistance - elapsedTime
        publish {
            self.ghostDistanceDeltaMeters = distanceDelta
            self.ghostTimeDeltaSeconds = timeDelta
            self.ghostComparisonUpdatedAt = Date()
        }

        evaluateGhostRaceCoach(
            configuration: ghost.audio,
            userDistance: userDistance,
            distanceDelta: distanceDelta,
            timeDelta: timeDelta
        )

        if let gap = ATHLTHGhostCourseProgressPolicy.ghostLeadPercent(
            runnerCourseMeters: userDistance,
            ghostCourseMeters: ghostAtTime,
            routeLengthMeters: ghost.routeDistanceMeters
        ), ATHLTHGhostCourseProgressPolicy.shouldAnnouncePercentGap(
            ghostLeadPercent: gap,
            lastAnnouncedPercent: ghostLastAnnouncedGapPercent,
            secondsSinceLast: ghostLastGapAlertAt.map {
                Date().timeIntervalSince($0)
            }
        ), let audio = ghost.audio, audio.enabled {
            ghostLastAnnouncedGapPercent = gap
            ghostLastGapAlertAt = Date()
            let percent = Int(abs(gap).rounded())
            deliverWorkoutAlert(
                english: gap > 0
                    ? "On the planned route, Ghost is about \(percent) percent ahead."
                    : "On the planned route, you are about \(percent) percent ahead.",
                norwegian: gap > 0
                    ? "På den planlagte ruten ligger Ghost omtrent \(percent) prosent foran."
                    : "På den planlagte ruten ligger du omtrent \(percent) prosent foran.",
                delivery: audio.resolvedImportantLeadChangeDelivery,
                haptic: .notification,
                priority: .ghostImportant
            )
        }
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

        let confirmedOvertake = ghostOvertakeTracker.observe(
            signedGapMeters: distanceDelta,
            elapsedSeconds: elapsedTime
        )

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

        var finalPhaseRemainingMeters:
            Double?

        if configuration
                .shouldAnnounceFinalPhase,
           !ghostFinalPhaseAnnounced {
            let totalDistance =
                ghostRaceConfiguration?
                    .routeDistanceMeters ??
                plannedRoute.map {
                    max(
                        $0.distanceKilometers *
                            1_000,
                        0
                    )
                }

            if let totalDistance,
               totalDistance > 0 {
                let remaining =
                    max(
                        totalDistance -
                            userDistance,
                        0
                    )

                if remaining > 0 &&
                    remaining <=
                        configuration
                            .resolvedFinalPhaseStartMeters {
                    ghostFinalPhaseAnnounced =
                        true
                    finalPhaseRemainingMeters =
                        remaining
                }
            }
        }

        if periodicAnnouncement ||
            finalPhaseRemainingMeters != nil {
            announceGhostRaceLead(
                distanceDelta:
                    distanceDelta,
                timeDelta:
                    timeDelta,
                delivery:
                    configuration
                        .resolvedPeriodicDelivery,
                priority:
                    .ghostPeriodic,
                configuration:
                    configuration,
                finalPhaseRemainingMeters:
                    finalPhaseRemainingMeters
            )
            lastGhostAnnouncedLeadMeters =
                distanceDelta
            // Periodic kilometre/time status must not consume the cooldown
            // for a real overtake or meaningful race event.
            lastGhostLeadSign =
                ghostLeadSign(
                    distanceDelta
                )
            return
        }

        guard (
            configuration
                .announceLeadChanges ||
            configuration
                .shouldAnnounceOvertakes
        ),
              elapsedTime >= 20
        else {
            return
        }

        let currentSign =
            ghostLeadSign(
                distanceDelta
            )
        let signChanged =
            confirmedOvertake &&
            currentSign != 0 &&
            lastGhostLeadSign != 0 &&
            currentSign !=
                lastGhostLeadSign &&
            abs(distanceDelta) >=
                configuration
                    .resolvedLeadFlipThresholdMeters

        let previousLead =
            lastGhostAnnouncedLeadMeters
        let absoluteLeadChange =
            previousLead.map {
                abs(
                    distanceDelta - $0
                )
            } ?? 0
        let movedEnough =
            configuration
                .announceLeadChanges &&
            absoluteLeadChange >=
                max(
                    configuration
                        .leadChangeThresholdMeters,
                    10
                )
        let overtakeDue =
            configuration
                .shouldAnnounceOvertakes &&
            signChanged
        let important =
            overtakeDue ||
            (
                configuration
                    .announceLeadChanges &&
                absoluteLeadChange >=
                    configuration
                        .resolvedImportantLeadChangeMeters
            )
        let requiredCooldown =
            important
                ? configuration
                    .resolvedImportantLeadChangeCooldownSeconds
                : configuration
                    .resolvedLeadChangeCooldownSeconds

        let cooldownSatisfied =
            lastGhostLeadAlertAt.map {
                Date().timeIntervalSince($0) >=
                    requiredCooldown
            } ?? true

        guard cooldownSatisfied &&
                (overtakeDue || movedEnough)
        else {
            if lastGhostAnnouncedLeadMeters == nil {
                lastGhostAnnouncedLeadMeters =
                    distanceDelta
                lastGhostLeadSign =
                    currentSign
            }
            return
        }

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
                    : .ghostPeriodic,
            configuration:
                configuration,
            finalPhaseRemainingMeters:
                nil
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
        priority: ATHLTHGuidancePriority,
        configuration:
            WatchGhostRaceAudioConfiguration,
        finalPhaseRemainingMeters:
            Double?
    ) {
        let meters =
            abs(distanceDelta)
        let mode =
            configuration
                .resolvedStatusDetailMode
        let includeDistance =
            mode != .time ||
            timeDelta == nil
        let includeTime =
            mode != .distance &&
            timeDelta != nil
        let opponent =
            currentGhostOpponentName

        var englishParts: [String] = []
        var norwegianParts: [String] = []

        if let finalPhaseRemainingMeters {
            englishParts.append(
                "Final " +
                ghostGapDistancePhrase(
                    finalPhaseRemainingMeters,
                    norwegian: false
                ) +
                "."
            )
            norwegianParts.append(
                "Siste " +
                ghostGapDistancePhrase(
                    finalPhaseRemainingMeters,
                    norwegian: true
                ) +
                "."
            )
        }

        // Explain the target instead of merely reading the gap. Only
        // a fixed Replay/Target Ghost has a meaningful target finish clock.
        // Live competitors can change pace and must not receive this cue.
        if let finalPhaseRemainingMeters,
           distanceDelta < -8,
           let fixedGhost = ghostRaceConfiguration,
           let targetPace = ATHLTHGhostFinishPaceCoach.requiredSecondsPerKilometre(
                remainingMeters: finalPhaseRemainingMeters,
                elapsedSeconds: elapsedTime,
                ghostFinishSeconds: fixedGhost.referenceDuration
           ) {
            let formatted = ATHLTHGhostFinishPaceCoach.minuteSecondText(targetPace)
            englishParts.append(
                "To catch the Ghost, aim for about \(formatted) per kilometre."
            )
            norwegianParts.append(
                "For å ta igjen Ghosten, sikt mot omtrent \(formatted) per kilometer."
            )
        }

        if meters < 8 {
            if let opponent {
                englishParts.append(
                    "You and \(opponent) are neck and neck."
                )
                norwegianParts.append(
                    "Du og \(opponent) ligger helt jevnt."
                )
            } else {
                englishParts.append(
                    "Ghost Race. Neck and neck."
                )
                norwegianParts.append(
                    "Ghost Race. Helt jevnt."
                )
            }
        } else if distanceDelta > 0 {
            if let opponent {
                if includeDistance {
                    englishParts.append(
                        "You are " +
                        ghostGapDistancePhrase(
                            meters,
                            norwegian: false
                        ) +
                        " ahead of \(opponent)."
                    )
                    norwegianParts.append(
                        "Du er " +
                        ghostGapDistancePhrase(
                            meters,
                            norwegian: true
                        ) +
                        " foran \(opponent)."
                    )
                }

                if includeTime,
                   let timeDelta {
                    if includeDistance {
                        englishParts.append(
                            "About " +
                            ghostGapTimePhrase(
                                abs(timeDelta),
                                norwegian: false
                            ) +
                            " ahead."
                        )
                        norwegianParts.append(
                            "Omtrent " +
                            ghostGapTimePhrase(
                                abs(timeDelta),
                                norwegian: true
                            ) +
                            " foran."
                        )
                    } else {
                        englishParts.append(
                            "You are about " +
                            ghostGapTimePhrase(
                                abs(timeDelta),
                                norwegian: false
                            ) +
                            " ahead of \(opponent)."
                        )
                        norwegianParts.append(
                            "Du er omtrent " +
                            ghostGapTimePhrase(
                                abs(timeDelta),
                                norwegian: true
                            ) +
                            " foran \(opponent)."
                        )
                    }
                }
            } else {
                if includeDistance {
                    englishParts.append(
                        "Ghost Race. You are " +
                        ghostGapDistancePhrase(
                            meters,
                            norwegian: false
                        ) +
                        " ahead."
                    )
                    norwegianParts.append(
                        "Ghost Race. Du er " +
                        ghostGapDistancePhrase(
                            meters,
                            norwegian: true
                        ) +
                        " foran."
                    )
                }

                if includeTime,
                   let timeDelta {
                    englishParts.append(
                        (includeDistance
                            ? "About "
                            : "Ghost Race. You are about ") +
                        ghostGapTimePhrase(
                            abs(timeDelta),
                            norwegian: false
                        ) +
                        " ahead."
                    )
                    norwegianParts.append(
                        (includeDistance
                            ? "Omtrent "
                            : "Ghost Race. Du er omtrent ") +
                        ghostGapTimePhrase(
                            abs(timeDelta),
                            norwegian: true
                        ) +
                        " foran."
                    )
                }
            }
        } else {
            if let opponent {
                if includeDistance {
                    englishParts.append(
                        "\(opponent) is " +
                        ghostGapDistancePhrase(
                            meters,
                            norwegian: false
                        ) +
                        " ahead."
                    )
                    norwegianParts.append(
                        "\(opponent) er " +
                        ghostGapDistancePhrase(
                            meters,
                            norwegian: true
                        ) +
                        " foran."
                    )
                }

                if includeTime,
                   let timeDelta {
                    if includeDistance {
                        englishParts.append(
                            "You are about " +
                            ghostGapTimePhrase(
                                abs(timeDelta),
                                norwegian: false
                            ) +
                            " behind."
                        )
                        norwegianParts.append(
                            "Du er omtrent " +
                            ghostGapTimePhrase(
                                abs(timeDelta),
                                norwegian: true
                            ) +
                            " bak."
                        )
                    } else {
                        englishParts.append(
                            "\(opponent) is about " +
                            ghostGapTimePhrase(
                                abs(timeDelta),
                                norwegian: false
                            ) +
                            " ahead."
                        )
                        norwegianParts.append(
                            "\(opponent) er omtrent " +
                            ghostGapTimePhrase(
                                abs(timeDelta),
                                norwegian: true
                            ) +
                            " foran."
                        )
                    }
                }
            } else {
                if includeDistance {
                    englishParts.append(
                        "Ghost Race. Your ghost is " +
                        ghostGapDistancePhrase(
                            meters,
                            norwegian: false
                        ) +
                        " ahead."
                    )
                    norwegianParts.append(
                        "Ghost Race. Ghosten er " +
                        ghostGapDistancePhrase(
                            meters,
                            norwegian: true
                        ) +
                        " foran."
                    )
                }

                if includeTime,
                   let timeDelta {
                    englishParts.append(
                        (includeDistance
                            ? "You are about "
                            : "Ghost Race. You are about ") +
                        ghostGapTimePhrase(
                            abs(timeDelta),
                            norwegian: false
                        ) +
                        " behind."
                    )
                    norwegianParts.append(
                        (includeDistance
                            ? "Du er omtrent "
                            : "Ghost Race. Du er omtrent ") +
                        ghostGapTimePhrase(
                            abs(timeDelta),
                            norwegian: true
                        ) +
                        " bak."
                    )
                }
            }
        }

        deliverWorkoutAlert(
            english:
                englishParts.joined(
                    separator: " "
                ),
            norwegian:
                norwegianParts.joined(
                    separator: " "
                ),
            delivery: delivery,
            haptic:
                distanceDelta >= 0
                    ? .success
                    : .notification,
            priority: priority
        )
    }

    private var currentGhostOpponentName:
        String? {
        let fixed =
            ghostRaceConfiguration?
                .opponentName?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        if let fixed,
           !fixed.isEmpty {
            return fixed
        }

        let live =
            liveSurfaceContext
                .liveGhost?
                .opponentName?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        if let live,
           !live.isEmpty {
            return live
        }

        return nil
    }

    private func ghostGapDistancePhrase(
        _ meters: Double,
        norwegian: Bool
    ) -> String {
        let value =
            max(meters, 0)

        if value >= 1_000 {
            return String(
                format: "%.1f km",
                value / 1_000
            )
        }

        let rounded =
            Int(value.rounded())
        return norwegian
            ? "\(rounded) meter"
            : "\(rounded) meters"
    }

    private func ghostGapTimePhrase(
        _ seconds: TimeInterval,
        norwegian: Bool
    ) -> String {
        let total =
            max(
                Int(seconds.rounded()),
                0
            )

        if total < 90 {
            return norwegian
                ? "\(total) sekunder"
                : "\(total) seconds"
        }

        let minutes =
            total / 60
        let remainder =
            total % 60

        if remainder == 0 {
            return norwegian
                ? "\(minutes) minutter"
                : "\(minutes) minutes"
        }

        return norwegian
            ? "\(minutes) minutter \(remainder) sekunder"
            : "\(minutes) minutes \(remainder) seconds"
    }

    private func announceLiveGhostConnectionChangeIfNeeded(
        previous: String?,
        current: String?,
        opponentName: String,
        configuration:
            WatchGhostRaceAudioConfiguration?
    ) {
        let normalizedCurrent =
            current?.uppercased()
        let normalizedPrevious =
            previous?.uppercased()

        lastLiveGhostConnectionText =
            normalizedCurrent

        guard isActive,
              kind == .running,
              let configuration,
              configuration.enabled,
              configuration
                .shouldAnnounceLiveConnectionChanges,
              let normalizedPrevious,
              let normalizedCurrent,
              normalizedPrevious !=
                normalizedCurrent
        else {
            return
        }

        let trimmedName =
            opponentName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let name =
            trimmedName.isEmpty
                ? ATHLTHLocalization.choose(
                    english: "your opponent",
                    norwegian: "motstanderen"
                )
                : trimmedName

        if normalizedCurrent == "LIVE",
           normalizedPrevious != "LIVE" {
            deliverWorkoutAlert(
                english:
                    "\(name) is live again.",
                norwegian:
                    "\(name) er live igjen.",
                delivery:
                    configuration
                        .resolvedImportantLeadChangeDelivery,
                haptic: .success,
                priority: .ghostImportant
            )
        } else if normalizedPrevious == "LIVE",
                  normalizedCurrent != "LIVE" {
            deliverWorkoutAlert(
                english:
                    "Live connection to \(name) is interrupted.",
                norwegian:
                    "Live-tilkoblingen til \(name) er avbrutt.",
                delivery:
                    configuration
                        .resolvedImportantLeadChangeDelivery,
                haptic: .notification,
                priority: .ghostImportant
            )
        }
    }

    private func ghostLeadSign(
        _ distanceDelta: Double
    ) -> Int {
        if abs(distanceDelta) < 8 {
            return 0
        }

        return distanceDelta > 0 ? 1 : -1
    }

    private func evaluateUpcomingRouteTurn(
        location: CLLocation,
        nearestIndex: Int,
        deviationMeters: Double
    ) {
        guard isActive, state == .running,
              routeAlertConfiguration.enabled,
              audioCoachConfiguration.enabled,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 25,
              deviationMeters <= routeAlertConfiguration.deviationMeters,
              let cue = ATHLTHRouteNavigationCue.nextTurn(
                  route: plannedRouteLocations.map(\.coordinate),
                  nearestIndex: nearestIndex
              ),
              let turnIndex = cue.pointIndex,
              (25...85).contains(cue.distanceMeters),
              lastSpokenRouteTurnIndex != turnIndex
        else { return }
        let now = Date()
        if let lastSpokenRouteTurnAt,
           now.timeIntervalSince(lastSpokenRouteTurnAt) < 35 { return }
        lastSpokenRouteTurnAt = now
        lastSpokenRouteTurnIndex = turnIndex

        let distance = spokenDistance(cue.distanceMeters)
        let isRight = cue.direction == .right
        deliverWorkoutAlert(
            english: "In \(distance), the route bends \(isRight ? "right" : "left").",
            norwegian: "Om \(distance) svinger ruten mot \(isRight ? "høyre" : "venstre").",
            delivery: routeAlertConfiguration.delivery,
            haptic: .notification,
            priority: .routeCritical
        )
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

        let recovery = routeNavigationCue
        let englishRecovery = recovery?.text(norwegian: false) ??
            "Move toward the highlighted route."
        let norwegianRecovery = recovery?.text(norwegian: true) ??
            "Gå mot den markerte ruten."
        deliverWorkoutAlert(
            english: "Off route by \(spokenDistance(deviationMeters)). " + englishRecovery,
            norwegian: "Du er \(spokenDistance(deviationMeters)) utenfor ruten. " +
                norwegianRecovery,
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

        let missingHeartRateSample =
            configuration.heartRateEnabled &&
            configuration.heartRateMinimumBPM != nil &&
            configuration.heartRateMaximumBPM != nil &&
            !ATHLTHCoachSensorFreshness.validHeartRate(
                heartRate,
                sampledAt: coachHeartRateSampleAt
            )
        let stepPaceTarget = currentStructuredRunningStep
        let missingPaceSample =
            configuration.paceAlertsEnabled &&
            (stepPaceTarget?.targetPaceMinSecondsPerKilometer != nil ||
             stepPaceTarget?.targetPaceMaxSecondsPerKilometer != nil) &&
            !ATHLTHCoachSensorFreshness.validPace(
                currentPaceSecondsPerKilometer,
                sampledAt: coachPaceSampleAt
            )

        if configuration.heartRateEnabled,
           ATHLTHCoachSensorFreshness.validHeartRate(
               heartRate,
               sampledAt: coachHeartRateSampleAt
           ),
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
           ATHLTHCoachSensorFreshness.validPace(
               currentPaceSecondsPerKilometer,
               sampledAt: coachPaceSampleAt
           ),
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

        // A different sensor being on target does not prove a stale
        // HR/pace signal has recovered. Avoid a false "back in target".
        if violation == nil,
           missingHeartRateSample || missingPaceSample {
            publish { self.liveTargetStatus = nil }
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
        let channels = ATHLTHCoachAlertChannels.resolve(
            delivery: delivery,
            voiceEnabled: liveSurfaceConfiguration.audioAlertsEnabled,
            hapticsEnabled: liveSurfaceConfiguration.hapticsEnabled,
            hapticPermittedByPriority:
                guidancePriorityGate.allowsHaptic(for: priority)
        )
        if channels.haptic {
            WKInterfaceDevice.current().play(haptic)
        }

        if channels.voice {
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
                .routineCoach,
        event: ATHLTHCoachEvent? = nil,
        forceLocal: Bool = false,
        rememberForReplay: Bool = true
    ) {
        guard !text.isEmpty,
              ATHLTHCoachVoicePausePolicy.allowsSpeech(
                  coachEnabled: audioCoachConfiguration.enabled,
                  speechPaused: coachSpeechPaused,
                  priority: priority
              )
        else { return }
        if let event,
           !coachEventLedger.canDeliver(event) {
            return
        }

        guard forceLocal || shouldSpeakLocally(priority: priority) else {
            // iPhone handles routine and structured running commentary.
            // Critical route/target alerts, Ghost and strength cues remain
            // local because the mirrored iPhone coach does not reproduce them.
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
            if priority >= .ghostImportant {
                let queuedEvent = event ??
                    ATHLTHCoachEventFallback.event(for: priority)
                coachCueQueue.enqueue(
                    ATHLTHCoachQueuedCue(
                        event: queuedEvent,
                        text: text
                    )
                )
            }
            return

        case .interruptAndDeliver:
            audioCoachSpeechWatchdog?.cancel()
            audioCoachSpeechWatchdog = nil
            audioCoachActivationTask?
                .cancel()
            audioCoachActivationTask = nil
            speechSynthesizer.stopSpeaking(
                at: .immediate
            )

        case .deliver:
            break
        }

        let spokenText = rememberForReplay
            ? (audioCoachConfiguration.speechStyle ?? .balanced).render(
                text,
                language: audioCoachConfiguration.language,
                priority: priority,
                eventKind: event?.kind
            )
            : text
        let utterance = AVSpeechUtterance(
            string: spokenText
        )

        utterance.voice = ATHLTHCoachPreferredSystemVoice.resolve(
            selectedIdentifier: audioCoachConfiguration.voiceIdentifier,
            language: audioCoachConfiguration.language
        )

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

                // An audio-route activation may outlast a short interval.
                // Drop expired commentary rather than speak stale guidance.
                if let event,
                   !event.isFresh() {
                    self.guidancePriorityGate.voiceDidFinish()
                    self.deactivateAudioCoachAudioSession()
                    return
                }

                // The mirror owner may have changed while the audio route
                // was activating. Re-check ownership and any phone receipt
                // before beginning the utterance or marking it delivered.
                guard ATHLTHCoachVoicePausePolicy.allowsSpeech(
                          coachEnabled: self.audioCoachConfiguration.enabled,
                          speechPaused: self.coachSpeechPaused,
                          priority: priority
                      ),
                      (forceLocal || self.shouldSpeakLocally(priority: priority)),
                      event.map({ self.coachEventLedger.canDeliver($0) }) ?? true
                else {
                    self.guidancePriorityGate.voiceDidFinish()
                    self.deactivateAudioCoachAudioSession()
                    return
                }

                if let event {
                    self.coachEventLedger.didDeliver(event)
                }
                self.speechSynthesizer.speak(utterance)
                self.watchCoachSpeechCompletion(utterance)
                if rememberForReplay,
                   ATHLTHCoachReplayMemory.mayRemember(priority: priority) {
                    self.coachReplayMemory.remember(
                        spokenText,
                        priority: priority
                    )
                    self.lastCoachMessage = self.coachReplayMemory.text
                }
                if let event {
                    self.reportWatchSpokenEventAttempt(event)
                }
            }
    }

    private func shouldSpeakLocally(
        priority: ATHLTHGuidancePriority
    ) -> Bool {
        // Preserve legacy reachability routing with an older paired iPhone;
        // upgraded peers use a short, explicitly acknowledged mirror lease.
        let phoneOwnsRoutineSpeech: Bool
        if audioCoachConfiguration.shouldUseAcknowledgedVoiceLease {
            phoneOwnsRoutineSpeech =
                mirroringActive && iPhoneVoiceLease.isActive()
        } else {
            phoneOwnsRoutineSpeech =
                WCSession.isSupported() &&
                WCSession.default.activationState == .activated &&
                WCSession.default.isReachable
        }
        return ATHLTHAudioCoachVoiceRouting.shouldSpeakOnWatch(
            configuration: audioCoachConfiguration,
            workoutKind: kind,
            priority: priority,
            iPhoneVoiceLeaseActive: phoneOwnsRoutineSpeech
        )
    }

    private func reportWatchSpokenEventAttempt(
        _ event: ATHLTHCoachEvent
    ) {
        guard mirroringActive,
              let startedAt,
              let workoutSession
        else { return }
        let receipt = ATHLTHCoachDeliveryReceipt(
            workoutStartedAt: startedAt,
            eventKind: event.kind,
            eventKey: event.key,
            sentAt: Date()
        )
        guard receipt.isValid(for: startedAt),
              let payload = try? JSONEncoder().encode(receipt)
        else { return }

        Task { @MainActor in
            try? await workoutSession.sendToRemoteWorkoutSession(
                data: payload
            )
        }
    }

    private func deliverNextQueuedCoachCue() {
        guard audioCoachConfiguration.enabled,
              isActive,
              !speechSynthesizer.isSpeaking,
              audioCoachActivationTask == nil,
              let next = coachCueQueue.popNext()
        else { return }

        // speak() rechecks the iPhone voice lease and existing priority gate.
        speak(
            next.text,
            priority: next.event.priority,
            event: next.event
        )
    }

    /// watchOS can miss AVSpeechSynthesizer's completion callback during a
    /// Bluetooth music route handoff. Don't leave a short cue's ducking lease
    /// active until another workout event happens to close it.
    private func watchCoachSpeechCompletion(_ utterance: AVSpeechUtterance) {
        audioCoachSpeechWatchdog?.cancel()
        let duration = max(
            20,
            min(90, Double(utterance.speechString.count) / 5 + 15)
        )
        audioCoachSpeechWatchdog = Task { @MainActor [weak self] in
            for _ in 0..<Int(ceil(duration)) {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard !Task.isCancelled, let self else { return }
                if !self.speechSynthesizer.isSpeaking {
                    self.audioCoachSpeechWatchdog = nil
                    guard self.audioCoachActivationTask == nil else { return }
                    self.guidancePriorityGate.voiceDidFinish()
                    self.deactivateAudioCoachAudioSession()
                    self.deliverNextQueuedCoachCue()
                    return
                }
            }
            guard !Task.isCancelled, let self,
                  self.audioCoachActivationTask == nil else { return }
            self.speechSynthesizer.stopSpeaking(at: .immediate)
            self.audioCoachSpeechWatchdog = nil
            self.guidancePriorityGate.voiceDidFinish()
            self.deactivateAudioCoachAudioSession()
            self.deliverNextQueuedCoachCue()
        }
    }

    private func activateAudioCoachAudioSession()
        async -> Bool {
        audioCoachRestorationTask?.cancel()
        audioCoachRestorationTask = nil
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
            // The alternate Watch route must preserve the SAME mixing
            // options. Previously the fallback discarded .duckOthers, so
            // some spoken cues lowered music and others did not.
            // WatchOS may select the built-in speaker or request another route.
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                policy: .longFormAudio,
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
        audioCoachSpeechWatchdog?.cancel()
        audioCoachSpeechWatchdog = nil
        guard coachAudioSessionIsActive else { return }
        audioCoachRestorationTask?.cancel()
        audioCoachRestorationTask = nil
        do {
            try AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
            coachAudioSessionIsActive = false
        } catch {
            // watchOS can temporarily refuse deactivation during AirPods /
            // music route handoff. Keep the active flag until deactivation
            // actually succeeds so the music never remains ducked silently.
            // The next speech activation cancels the retry.
            audioCoachRestorationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled, self.coachAudioSessionIsActive {
                    do { try await Task.sleep(for: .seconds(2)) }
                    catch { return }
                    guard !Task.isCancelled else { return }
                    // Never deactivate the session of a newer cue.
                    if self.speechSynthesizer.isSpeaking ||
                       self.audioCoachActivationTask != nil { return }
                    do {
                        try AVAudioSession.sharedInstance().setActive(
                            false, options: .notifyOthersOnDeactivation)
                        self.coachAudioSessionIsActive = false
                        self.audioCoachRestorationTask = nil
                        return
                    } catch { continue }
                }
            }
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
        recordRunningMinuteIfDue(force: true)
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

        if kind == .running || kind == .walking {
            result.recordedRunningMinutes = recordedStructuredRunMinutes
        }

        if structuredWorkoutComplete,
           let structured = structuredRunningWorkout,
           !structured.steps.isEmpty,
           recordedStructuredRunSteps.count == structured.steps.count {
            result.structuredWorkoutFullyCompleted = true
            result.structuredWorkoutSourceID = structured.sourceWorkoutID
            result.structuredWorkoutTitle = structured.title
            result.recordedRunningSteps = recordedStructuredRunSteps
            result.recordedRunningMinutes = recordedStructuredRunMinutes
        }

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
            structuredWorkoutComplete ? nil : currentStructuredRunningStep
        let runningStepReadout = currentRunningStep.map {
            ATHLTHRunIntervalReadout.resolve(
                step: $0,
                elapsedSeconds: currentStructuredStepElapsedTime,
                distanceMeters: currentStructuredStepDistanceMeters
            )
        }
        let runningStepProgress =
            currentRunningStep.map {
                if awaitingMainStart { return 0.0 }
                return ATHLTHRunningStepEngine.progress(
                    step: $0,
                    elapsedTime: elapsedTime,
                    distanceMeters: distanceMeters,
                    stepStartElapsedTime:
                        structuredStepStartElapsedTime,
                    stepStartDistanceMeters:
                        structuredStepStartDistanceMeters
                )
            }

        var snapshot = WatchWorkoutLiveSnapshot(
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
            currentHorizontalAccuracy:
                lastAcceptedOutdoorLocation?.horizontalAccuracy,
            currentLocationSampledAt:
                lastAcceptedOutdoorLocation?.timestamp,
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
                (kind == .strength ? strengthSession?.title : nil) ??
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
            routeCueEnglish: routeNavigationCue?.text(norwegian: false),
            routeCueNorwegian: routeNavigationCue?.text(norwegian: true),
            routeCueSymbol: routeNavigationCue?.symbol,
            routeCueDistanceMeters: routeNavigationCue?.distanceMeters,
            routeCueOffRoute: routeNavigationCue?.offRoute,
            routeCanReturnToStart: canRunBackToStart,
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
            runningStepRemainingSeconds:
                runningStepReadout?.unit == .seconds
                    ? runningStepReadout?.remaining : nil,
            runningStepRemainingMeters:
                runningStepReadout?.unit == .meters
                    ? runningStepReadout?.remaining : nil,
            runningStepCoachBrief: currentRunningStep?.coachBrief,
            runningStepPhase: currentRunningStep?.phase,
            runningStepTargetHeartRateZone: currentRunningStep?.targetHeartRateZone,
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
            strengthNextExerciseName:
                strengthSession.flatMap { snapshot in
                    guard let pending = snapshot.exerciseQueue?.filter({
                        $0.index != snapshot.exerciseIndex &&
                        $0.isCompleted != true
                    }) else { return nil }
                    return (pending.first(where: {
                        $0.index > snapshot.exerciseIndex
                    }) ?? pending.first)?.name
                },
            strengthTimedSetTargetSeconds:
                strengthSession?.draftDurationSeconds,
            strengthTimedSetSecondsAtSnapshot:
                strengthSession?.timedSetCountdown?.remaining(at: now),
            strengthTimedSetResumedAt:
                strengthSession?.timedSetCountdown?.isRunning == true
                    ? now : nil,
            liveSurfaceConfiguration:
                liveSurfaceConfiguration,
            liveSurfaceContext:
                liveSurfaceContext,
            supportsAudioCoachVoiceLease: true,
            coachHeartRateSampleAt: coachHeartRateSampleAt,
            coachPaceSampleAt: coachPaceSampleAt
        )

        if let progress = runningStepProgress, let structure = structuredRunningWorkout {
            snapshot.runningOverallProgress = ATHLTHRunningStepEngine.overallProgress(
                steps: structure.steps, index: structuredStepIndex,
                currentStepProgress: awaitingMainStart ? 0 : progress
            )
        }
        snapshot.treadmillTargetPaceSecondsPerKilometer =
            treadmillTargetPaceSecondsPerKilometer
        snapshot.runningStepTargetTreadmillInclinePercent =
            currentRunningStep?.targetTreadmillInclinePercent
        snapshot.runningStepTargetPaceSecondsPerKilometer =
            currentRunningStep?.targetPaceMinSecondsPerKilometer
        snapshot.runningAwaitingMainStart = awaitingMainStart
        snapshot.runningRouteWarmup =
            structuredRunningWorkout?.deferRouteUntilMain == true &&
            currentRunningStep?.phase == "warmup"
        if let step = currentRunningStep {
            snapshot.runningManualAdvanceRequired =
                awaitingMainStart ||
                (step.phase == "warmup" &&
                 structuredRunningWorkout?.autoStartMainAfterWarmup != true) ||
                step.phase == "cooldown" ||
                step.measure == .open ||
                structuredRunningWorkout?.autoAdvanceTimedSteps == false
            snapshot.runningStepElapsedSeconds =
                awaitingMainStart ? 0 : currentStructuredStepElapsedTime
        }
        snapshot.runningIntervalCoachCueEverySeconds =
            structuredRunningWorkout?.intervalCoachCueEverySeconds
        snapshot.runningIntervalCoachCountdownSeconds =
            structuredRunningWorkout?.intervalCoachCountdownSeconds

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
            case .strength where collectingHybridTreadmillDistance:
                return .distanceWalkingRunning
            case .strength, .hiit, .functional, .rowing, .stairClimbing, .yoga, .other:
                return nil
            }
        }()
        let distanceType = distanceIdentifier.flatMap {
            HKObjectType.quantityType(forIdentifier: $0)
        }

        if let heartType, types.contains(heartType),
           let statistics = builder.statistics(for: heartType),
           let latestQuantity = statistics.mostRecentQuantity() {
            let unit = HKUnit.count().unitDivided(by: .minute())
            let latest = latestQuantity.doubleValue(for: unit)
            coachHeartRateSampleAt = Date()
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
            // Also honor system-initiated resume (Siri, workout UI, or
            // recovery). Explicit resume() already updated the clock, so
            // this only fills gaps without duplicating journal commands.
            if previousState == .paused,
               strengthSession?.isEmbeddedRunningInterval == true,
               let countdown = strengthSession?.timedSetCountdown,
               !countdown.isRunning, countdown.remaining(at: date) > 0 {
                startOrResumeTimedStrengthSet(allowIPhoneOnly: true)
            }
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
            // Cover pauses originating outside our own pause button.
            if previousState == .running,
               strengthSession?.isEmbeddedRunningInterval == true,
               strengthSession?.timedSetCountdown?.isRunning == true {
                pauseTimedStrengthSet(allowIPhoneOnly: true)
            }
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
        reportWorkoutActivityStateToPhone(
            newState
        )
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

            self.audioCoachSpeechWatchdog?.cancel()
            self.audioCoachSpeechWatchdog = nil
            self.guidancePriorityGate
                .voiceDidFinish()
            self.deactivateAudioCoachAudioSession()
            self.deliverNextQueuedCoachCue()
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

            self.audioCoachSpeechWatchdog?.cancel()
            self.audioCoachSpeechWatchdog = nil
            self.guidancePriorityGate
                .voiceDidFinish()
            self.deactivateAudioCoachAudioSession()
            self.deliverNextQueuedCoachCue()
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
                if let receipt = try? JSONDecoder().decode(
                    ATHLTHCoachDeliveryReceipt.self,
                    from: payload
                ) {
                    if receipt.isValid(for: self.startedAt) {
                        self.coachEventLedger.noteCompanionDelivery(
                            id: receipt.deliveryID
                        )
                    }
                    continue
                }

                if let offer = try? JSONDecoder().decode(
                    ATHLTHAudioCoachLeaseOffer.self,
                    from: payload
                ) {
                    let eligible =
                        self.mirroringActive &&
                        self.audioCoachConfiguration.enabled &&
                        self.audioCoachConfiguration
                            .shouldPreferIPhoneAudioWhenReachable &&
                        self.audioCoachConfiguration
                            .shouldUseAcknowledgedVoiceLease &&
                        (self.kind == .running ||
                         self.kind == .walking) &&
                        self.isActive

                    if let acknowledgement =
                        self.iPhoneVoiceLease.grant(
                            offer: offer,
                            workoutStartedAt: self.startedAt,
                            eligible: eligible
                        ),
                       let session = self.workoutSession,
                       let response = try? JSONEncoder()
                           .encode(acknowledgement) {
                        Task { @MainActor in
                            try? await session.sendToRemoteWorkoutSession(
                                data: response
                            )
                        }
                    }
                    continue
                }

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
                case .returnToStart:
                    // This can arrive delayed after a reconnect. It must
                    // never redirect a later workout or an older session.
                    if let requested = command.workoutStartedAt,
                       let startedAt = self.startedAt,
                       abs(requested.timeIntervalSince(startedAt)) < 5 {
                        self.startReturnToRouteStart()
                    }
                case .end:
                    self.end()
                case .pause:
                    self.pause()
                case .resume:
                    self.resume()
                case .setTreadmillIncline:
                    if let value = command.treadmillInclinePercent {
                        self.setTreadmillInclinePercent(value)
                    }
                case .setTreadmillTargetPace:
                    if let value = command.treadmillTargetPaceSecondsPerKilometer,
                       let requested = command.workoutStartedAt,
                       let activeStart = self.startedAt,
                       abs(requested.timeIntervalSince(activeStart)) < 5 {
                        self.setTreadmillTargetPaceSecondsPerKilometer(value)
                    }
                case .advanceRunningStep:
                    if let requestedStart = command.workoutStartedAt,
                       let activeStart = self.startedAt,
                       abs(requestedStart.timeIntervalSince(activeStart)) < 5,
                       let expected = command.expectedRunningStepIndex,
                       expected == self.structuredStepIndex,
                       self.currentStructuredRunningStep != nil {
                        if command.startMainAfterWarmup == true {
                            if self.awaitingMainStart {
                                self.advanceStructuredRunningWorkoutManually()
                            }
                        } else if !self.awaitingMainStart {
                            self.advanceStructuredRunningWorkoutManually()
                        }
                    }
                case .appendRunningWorkout:
                    if let part = command.runningWorkoutToAppend {
                        self.appendRunningPart(
                            part,
                            startNow: command.runningWorkoutStartImmediately ?? false,
                            commandID: command.commandID,
                            requestedWorkoutStart: command.workoutStartedAt
                        )
                    }
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

            if self.usesOutdoorGPS {
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

        // Treadmill sessions must not consume GPS points, pace or auto-pause.
        guard usesOutdoorGPS else { return }

        let orderedLocations =
            filtered.sorted {
                $0.timestamp < $1.timestamp
            }

        if kind == .running {
            for location in orderedLocations {
                collectIndoorProbe(location)
            }
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
              usesOutdoorGPS,
              (kind == .running || kind == .walking)
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
