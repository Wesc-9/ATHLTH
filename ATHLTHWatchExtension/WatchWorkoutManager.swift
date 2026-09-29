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
    @Published private(set) var lapCount = 0
    @Published private(set) var currentLapElapsedTime: TimeInterval = 0
    @Published private(set) var currentLapDistanceMeters: Double = 0
    @Published private(set) var averageHeartRate: Double?
    @Published private(set) var maxHeartRate: Double?
    @Published private(set) var routePoints: [WatchRoutePoint] = []
    @Published private(set) var plannedRoute: WatchRouteTransfer?
    @Published private(set) var audioCoachConfiguration:
        WatchAudioCoachConfiguration = .disabled
    @Published private(set) var structuredRunningWorkout:
        WatchRunningWorkoutTransfer?
    @Published private(set) var structuredStepIndex = 0
    @Published private(set) var strengthSession:
        WatchStrengthSessionSnapshot?
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
    private var offRouteStartedAt: Date?
    private var lastOffRouteAlertAt: Date?
    private var routeWasOff = false
    private var targetViolationStartedAt: Date?
    private var lastTargetAlertAt: Date?
    private var targetWasOutside = false
    private var lastLapElapsedTime: TimeInterval = 0
    private var lastLapDistanceMeters: Double = 0

    private override init() {
        super.init()
        locationManager.delegate = self
        speechSynthesizer.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3
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
    }

    func configureAudioCoach(
        _ configuration: WatchAudioCoachConfiguration
    ) {
        publish {
            self.audioCoachConfiguration = configuration
        }
        resetAudioCoachThresholds()

        if isActive,
           configuration.enabled,
           currentStructuredRunningStep != nil {
            announceCurrentStructuredStep(prefix: "Current")
        }
    }

    func updateAudioCoachDuringWorkout(
        _ configuration: WatchAudioCoachConfiguration
    ) {
        publish {
            self.audioCoachConfiguration = configuration
        }

        resetAudioCoachThresholds()

        if !configuration.enabled {
            speechSynthesizer.stopSpeaking(at: .immediate)
            deactivateAudioCoachAudioSession()
        }
    }

    func configureRunningWorkout(
        _ workout: WatchRunningWorkoutTransfer
    ) {
        publish {
            self.structuredRunningWorkout =
                workout.steps.isEmpty ? nil : workout
            self.structuredStepIndex = 0

            if let routeAlerts = workout.routeAlerts {
                self.routeAlertConfiguration =
                    routeAlerts
            }

            self.targetAlertConfiguration =
                workout.targetAlerts
            self.liveTargetStatus = nil
        }

        structuredStepStartElapsedTime = elapsedTime
        structuredStepStartDistanceMeters = distanceMeters
        structuredWorkoutComplete = false
        offRouteStartedAt = nil
        lastOffRouteAlertAt = nil
        routeWasOff = false
        targetViolationStartedAt = nil
        lastTargetAlertAt = nil
        targetWasOutside = false

        if isActive,
           !workout.steps.isEmpty {
            announceCurrentStructuredStep(prefix: "Starting")
        }
    }

    func configureGhostRace(
        _ ghost: WatchGhostRaceTransfer?
    ) {
        ghostRaceConfiguration = ghost
        lastGhostAnnouncedLeadMeters = nil
        lastGhostLeadAlertAt = nil
        lastGhostLeadSign = 0

        if let interval =
                ghost?.audio?.distanceIntervalMeters,
           interval > 0 {
            nextGhostDistanceAnnouncementMeters =
                (
                    floor(
                        max(distanceMeters, 0) /
                        interval
                    ) + 1
                ) * interval
        } else {
            nextGhostDistanceAnnouncementMeters = nil
        }

        if let interval =
                ghost?.audio?.timeIntervalSeconds,
           interval > 0 {
            nextGhostTimeAnnouncementSeconds =
                (
                    floor(
                        max(elapsedTime, 0) /
                        interval
                    ) + 1
                ) * interval
        } else {
            nextGhostTimeAnnouncementSeconds = nil
        }

        publish {
            self.ghostRaceTitle = ghost?.title
            self.ghostDistanceDeltaMeters = nil
            self.ghostTimeDeltaSeconds = nil
        }
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

        if enabled {
            WKInterfaceDevice.current().play(.click)
            if currentStructuredRunningStep != nil {
                announceCurrentStructuredStep(
                    prefix: "Current"
                )
            }
        } else {
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

        lapCount += 1
        lastLapElapsedTime = elapsedTime
        lastLapDistanceMeters = distanceMeters
        currentLapElapsedTime = 0
        currentLapDistanceMeters = 0

        WKInterfaceDevice.current().play(.click)
    }

    func configureStrengthSession(
        _ snapshot: WatchStrengthSessionSnapshot
    ) {
        publish {
            self.strengthSession = snapshot
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
        publish {
            self.liveSurfaceContext = context
        }
    }

    func updateStrengthDraft(
        reps: Int? = nil,
        weightKilograms: Double? = nil,
        restSeconds: Int? = nil
    ) {
        guard var snapshot = strengthSession else {
            requestStrengthSnapshot()
            return
        }

        if let reps {
            snapshot.draftReps = max(reps, 0)
        }
        if let weightKilograms {
            snapshot.draftWeightKilograms =
                max(weightKilograms, 0)
        }
        if let restSeconds {
            snapshot.draftRestSeconds =
                min(max(restSeconds, 0), 600)
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
                addRestSeconds: nil,
                sentAt: Date()
            )
        )
    }

    func completeStrengthSet() {
        guard let snapshot = strengthSession else {
            requestStrengthSnapshot()
            return
        }

        sendStrengthCommand(
            WatchStrengthCommand(
                id: UUID(),
                workoutID: snapshot.workoutID,
                kind: .completeSet,
                reps: snapshot.draftReps,
                weightKilograms:
                    snapshot.draftWeightKilograms,
                restSeconds:
                    snapshot.draftRestSeconds,
                addRestSeconds: nil,
                sentAt: Date()
            )
        )
    }

    func skipStrengthRest() {
        guard let snapshot = strengthSession else {
            return
        }

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
    }

    func addStrengthRest(seconds: Int = 30) {
        guard let snapshot = strengthSession else {
            return
        }

        sendStrengthCommand(
            WatchStrengthCommand(
                id: UUID(),
                workoutID: snapshot.workoutID,
                kind: .addRest,
                reps: nil,
                weightKilograms: nil,
                restSeconds: nil,
                addRestSeconds: max(seconds, 0),
                sentAt: Date()
            )
        )
    }

    func moveToNextStrengthExercise() {
        guard let snapshot = strengthSession else {
            return
        }

        sendStrengthCommand(
            WatchStrengthCommand(
                id: UUID(),
                workoutID: snapshot.workoutID,
                kind: .nextExercise,
                reps: nil,
                weightKilograms: nil,
                restSeconds: nil,
                addRestSeconds: nil,
                sentAt: Date()
            )
        )
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
                sentAt: Date()
            )
        )
    }

    private func sendStrengthCommand(
        _ command: WatchStrengthCommand
    ) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(command)
        else {
            return
        }

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind:
                WatchTransferKind.strengthCommand.rawValue,
            WatchTransferMetadataKey.payload:
                data
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(
                payload,
                replyHandler: nil
            ) { _ in
                WCSession.default.transferUserInfo(
                    payload
                )
            }
        } else {
            WCSession.default.transferUserInfo(
                payload
            )
        }
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

    func start(
        kind: WatchWorkoutKind,
        route: WatchRouteTransfer? = nil
    ) async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType(for: kind)
        configuration.locationType = kind.usesOutdoorLocation ? .outdoor : .indoor

        await start(
            configuration: configuration,
            kind: kind,
            route: route
        )
    }

    func start(configuration: HKWorkoutConfiguration) async {
        let resolvedKind = kind(for: configuration.activityType)
        await start(
            configuration: configuration,
            kind: resolvedKind,
            route: nil
        )
    }

    func pause() {
        guard state == .running else { return }
        workoutSession?.pause()
    }

    func resume() {
        guard state == .paused else { return }
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
        speechSynthesizer.stopSpeaking(at: .immediate)
        deactivateAudioCoachAudioSession()
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
            self.averageHeartRate = nil
            self.maxHeartRate = nil
            self.routePoints = []
            self.plannedRoute = nil
            self.audioCoachConfiguration = .disabled
            self.structuredRunningWorkout = nil
            self.structuredStepIndex = 0
            self.strengthSession = nil
            self.liveSurfaceContext = .empty
            self.completedResult = nil
            self.errorMessage = nil
        }
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
            self.audioCoachConfiguration = .disabled
            self.structuredRunningWorkout = nil
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
            self.routeAlertConfiguration = .standard
            self.targetAlertConfiguration = nil
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
        offRouteStartedAt = nil
        lastOffRouteAlertAt = nil
        routeWasOff = false
        targetViolationStartedAt = nil
        lastTargetAlertAt = nil
        targetWasOutside = false
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
                locationManager.startUpdatingLocation()
            } else if kind == .strength,
                      locationManager.authorizationStatus == .authorizedWhenInUse ||
                      locationManager.authorizationStatus == .authorizedAlways {
                locationManager.requestLocation()
            }

            publishState(.running)
            startTimer()

            if kind == .strength {
                requestStrengthSnapshot()
            }

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

        var shareTypes: Set<HKSampleType> = [
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
                shareTypes.insert(type)
                readTypes.insert(type)
            }
        }

        try await healthStore.requestAuthorization(
            toShare: shareTypes,
            read: readTypes
        )
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
            speak(metricsAnnouncement)
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
                    )
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

        speak(parts.joined(separator: ". "))
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
                guidance.traveledAlongRouteMeters
        )

        evaluateRouteAlert(
            deviationMeters:
                guidance.deviationMeters,
            horizontalAccuracy:
                location.horizontalAccuracy
        )
    }

    private func updateGhostRace(
        traveledAlongRoute: Double
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

    private func evaluateGhostRaceCoach(
        configuration:
            WatchGhostRaceAudioConfiguration?,
        userDistance: Double,
        distanceDelta: Double,
        timeDelta: TimeInterval
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
                    configuration.delivery
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

        announceGhostRaceLead(
            distanceDelta:
                distanceDelta,
            timeDelta:
                timeDelta,
            delivery:
                configuration.delivery
        )

        lastGhostAnnouncedLeadMeters =
            distanceDelta
        lastGhostLeadAlertAt = Date()
        lastGhostLeadSign =
            currentSign
    }

    private func announceGhostRaceLead(
        distanceDelta: Double,
        timeDelta: TimeInterval,
        delivery: WatchAlertDelivery
    ) {
        let meters =
            abs(distanceDelta)
        let seconds =
            abs(timeDelta)

        let english: String
        let norwegian: String

        if meters < 8 {
            english =
                "Ghost Race. Neck and neck."
            norwegian =
                "Spøkelsesløp. Helt jevnt."
        } else if distanceDelta > 0 {
            english =
                "Ghost Race. You are " +
                spokenDistance(meters) +
                " ahead. About " +
                spokenDuration(seconds) +
                " ahead."
            norwegian =
                "Spøkelsesløp. Du er " +
                spokenDistance(meters) +
                " foran. Omtrent " +
                spokenDuration(seconds) +
                " foran."
        } else {
            english =
                "Ghost Race. Your ghost is " +
                spokenDistance(meters) +
                " ahead. About " +
                spokenDuration(seconds) +
                " behind."
            norwegian =
                "Spøkelsesløp. Spøkelset er " +
                spokenDistance(meters) +
                " foran. Omtrent " +
                spokenDuration(seconds) +
                " bak."
        }

        deliverWorkoutAlert(
            english: english,
            norwegian: norwegian,
            delivery: delivery,
            haptic:
                distanceDelta >= 0
                    ? .success
                    : .notification
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

        deliverWorkoutAlert(
            english:
                "You are off route. " +
                spokenDistance(deviationMeters),
            norwegian:
                "Du er utenfor ruten. " +
                spokenDistance(deviationMeters),
            delivery:
                configuration.delivery,
            haptic: .directionDown
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
                        haptic: .success
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
            haptic: .notification
        )
    }

    private func deliverWorkoutAlert(
        english: String,
        norwegian: String,
        delivery: WatchAlertDelivery,
        haptic: WKHapticType
    ) {
        if delivery.usesHaptics {
            WKInterfaceDevice.current()
                .play(haptic)
        }

        if delivery.usesVoice {
            speak(
                coachPhrase(
                    english: english,
                    norwegian: norwegian
                )
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
        _ text: String
    ) {
        guard !text.isEmpty else { return }

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(
                at: .word
            )
        }

        activateAudioCoachAudioSession()

        let utterance = AVSpeechUtterance(
            string: text
        )
        if let audioCoachVoiceLanguage,
           let voice = AVSpeechSynthesisVoice(
                language: audioCoachVoiceLanguage
           ) {
            utterance.voice = voice
        }
        utterance.rate = 0.48
        utterance.volume = 1.0
        speechSynthesizer.speak(utterance)
    }

    private func activateAudioCoachAudioSession() {
        let session = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions =
            audioCoachConfiguration.shouldDuckOtherAudio
                ? [
                    .duckOthers,
                    .interruptSpokenAudioAndMixWithOthers
                ]
                : [.mixWithOthers]

        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: options
            )
            try session.setActive(true)
            coachAudioSessionIsActive = true
        } catch {
            // Speech should still be attempted. A temporary audio-session
            // failure must never interrupt or end an active workout.
            errorMessage =
                "Audio Coach: \(error.localizedDescription)"
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
        let start = startedAt ?? workout.startDate
        let result = WatchWorkoutResult(
            id: UUID(),
            kind: kind,
            healthKitWorkoutUUID: workout.uuid,
            startedAt: start,
            endedAt: endDate,
            duration: max(workout.duration, elapsedTime),
            activeCalories: activeCalories,
            distanceMeters: distanceMeters,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            routePointCount: routePoints.count
        )

        sendToPhone(result)

        publish {
            self.completedResult = result
            self.elapsedTime = result.duration
            self.state = .completed
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            await self.sendLiveSnapshot(
                stateOverride: .completed,
                force: true
            )

            if self.mirroringActive,
               let workoutSession = self.workoutSession {
                try? await workoutSession
                    .stopMirroringToCompanionDevice()
                self.mirroringActive = false
            }
        }
    }

    private func sendToPhone(_ result: WatchWorkoutResult) {
        guard
            WCSession.isSupported(),
            let data = try? JSONEncoder().encode(result)
        else {
            return
        }

        WCSession.default.transferUserInfo([
            WatchTransferMetadataKey.kind: WatchTransferKind.workoutResult.rawValue,
            WatchTransferMetadataKey.payload: data
        ])
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
            publish {
                self.distanceMeters = quantity.doubleValue(for: .meter())
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

    private func handleWorkoutSessionState(
        _ state: HKWorkoutSessionState,
        date: Date
    ) {
        switch state {
        case .running:
            publishState(.running)

            if kind == .strength {
                requestStrengthSnapshot()
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

            Task { @MainActor [weak self] in
                await self?.sendLiveSnapshot(
                    stateOverride: .paused,
                    force: true
                )
            }

        case .ended:
            publishState(.ending)

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
        errorMessage = message
        state = .failed(message)

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
        publish {
            self.errorMessage = error.localizedDescription
            self.state = .failed(error.localizedDescription)
        }

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
                  self.kind == .strength,
                  self.state == .running
            else {
                return
            }

            self.locationManager
                .requestLocation()
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

        let startIndex =
            routePoints.count
        routePoints.append(
            contentsOf:
                filtered.enumerated().map {
                    offset,
                    location in

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
                            startIndex +
                            offset
                    )
                }
        )
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
    case collectionCouldNotStart
    case collectionCouldNotEnd
    case workoutCouldNotSave

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "HealthKit isn't available on this Apple Watch."
        case .collectionCouldNotStart:
            return "ATHLTH couldn't start workout data collection."
        case .collectionCouldNotEnd:
            return "ATHLTH couldn't finish workout data collection."
        case .workoutCouldNotSave:
            return "ATHLTH couldn't save the workout to Apple Health."
        }
    }
}
