import AVFoundation
import CoreLocation
import Foundation
import HealthKit
import WatchConnectivity

enum WatchWorkoutState: Equatable {
    case idle
    case preparing
    case running
    case paused
    case ending
    case completed
    case failed(String)
}

final class WatchWorkoutManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutManager()

    @Published private(set) var state: WatchWorkoutState = .idle
    @Published private(set) var kind: WatchWorkoutKind = .running
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var heartRate: Double = 0
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var distanceMeters: Double = 0
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
    private var nextDistanceAnnouncementMeters: Double?
    private var nextTimeAnnouncementSeconds: TimeInterval?
    private var structuredStepStartElapsedTime: TimeInterval = 0
    private var structuredStepStartDistanceMeters: Double = 0
    private var structuredWorkoutComplete = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3
    }

    func configurePlannedRoute(
        _ route: WatchRouteTransfer?
    ) {
        publish {
            self.plannedRoute = route
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

    func configureRunningWorkout(
        _ workout: WatchRunningWorkoutTransfer
    ) {
        publish {
            self.structuredRunningWorkout =
                workout.steps.isEmpty ? nil : workout
            self.structuredStepIndex = 0
        }
        structuredStepStartElapsedTime = elapsedTime
        structuredStepStartDistanceMeters = distanceMeters
        structuredWorkoutComplete = false

        if isActive,
           !workout.steps.isEmpty {
            announceCurrentStructuredStep(prefix: "Starting")
        }
    }

    func configureStrengthSession(
        _ snapshot: WatchStrengthSessionSnapshot
    ) {
        publish {
            self.strengthSession = snapshot
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
        speechSynthesizer.stopSpeaking(at: .immediate)
        publish {
            self.state = .idle
            self.elapsedTime = 0
            self.heartRate = 0
            self.activeCalories = 0
            self.distanceMeters = 0
            self.averageHeartRate = nil
            self.maxHeartRate = nil
            self.routePoints = []
            self.plannedRoute = nil
            self.audioCoachConfiguration = .disabled
            self.structuredRunningWorkout = nil
            self.structuredStepIndex = 0
            self.strengthSession = nil
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
            self.averageHeartRate = nil
            self.maxHeartRate = nil
            self.routePoints = []
        }
        workoutLocation = nil
        workoutLocationMetadataAttached = false
        structuredStepStartElapsedTime = 0
        structuredStepStartDistanceMeters = 0
        structuredWorkoutComplete = false
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

        publish {
            self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
                [weak self] _ in
                guard let self, let builder = self.workoutBuilder else { return }
                self.publish {
                    self.elapsedTime = builder.elapsedTime
                }
                self.evaluateStructuredRunningWorkout()
                self.evaluateAudioCoach()

                Task { [weak self] in
                    await self?.sendLiveSnapshot()
                }
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
            speak(metricsAnnouncement)
        }
    }

    private func evaluateStructuredRunningWorkout() {
        guard state == .running,
              kind == .running,
              !structuredWorkoutComplete,
              let step = currentStructuredRunningStep
        else {
            return
        }

        let completed: Bool

        switch step.measure {
        case .time:
            guard let duration = step.durationSeconds else {
                return
            }
            completed =
                elapsedTime - structuredStepStartElapsedTime >=
                duration

        case .distance:
            guard let distance = step.distanceMeters else {
                return
            }
            completed =
                distanceMeters - structuredStepStartDistanceMeters >=
                distance

        case .open:
            completed = false
        }

        guard completed else { return }
        advanceStructuredRunningWorkout()
    }

    private func advanceStructuredRunningWorkout() {
        guard let workout = structuredRunningWorkout else {
            return
        }

        let nextIndex = structuredStepIndex + 1

        guard workout.steps.indices.contains(nextIndex) else {
            structuredWorkoutComplete = true
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

        publish {
            self.structuredStepIndex = nextIndex
        }

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
            let remainingMeters = max(
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

        builder.endCollection(withEnd: endDate) { [weak self] success, error in
            guard let self else { return }

            if let error {
                self.fail(error)
                return
            }

            guard success else {
                self.fail(WatchWorkoutError.collectionCouldNotEnd)
                return
            }

            builder.finishWorkout { [weak self] workout, error in
                guard let self else { return }

                if let error {
                    self.fail(error)
                    return
                }

                guard let workout else {
                    self.fail(WatchWorkoutError.workoutCouldNotSave)
                    return
                }

                self.finishRouteIfNeeded(
                    workout: workout,
                    endDate: endDate
                )
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

        routeBuilder.finishRoute(with: workout, metadata: nil) {
            [weak self] _, error in
            guard let self else { return }

            if let error {
                self.publish {
                    self.errorMessage = "Workout saved, but the GPS route could not be attached: \(error.localizedDescription)"
                }
            }

            self.complete(workout: workout, endDate: endDate)
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

        Task { [weak self] in
            guard let self else { return }

            await self.sendLiveSnapshot(
                stateOverride: .completed,
                force: true
            )

            if self.mirroringActive,
               let workoutSession = self.workoutSession {
                try? await workoutSession.stopMirroringToCompanionDevice()
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
            routePointCount: routePoints.count
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

    private func fail(_ error: Error) {
        stopTimer()
        locationManager.stopUpdatingLocation()
        publish {
            self.errorMessage = error.localizedDescription
            self.state = .failed(error.localizedDescription)
        }

        Task { [weak self] in
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

    private func publish(_ changes: @escaping () -> Void) {
        if Thread.isMainThread {
            changes()
        } else {
            DispatchQueue.main.async(execute: changes)
        }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        switch toState {
        case .running:
            publishState(.running)

            if kind == .strength {
                requestStrengthSnapshot()
            }

            Task {
                await retryMirroringIfNeeded(
                    workoutSession
                )
                await sendLiveSnapshot(
                    stateOverride: .running,
                    force: true
                )
            }
        case .paused:
            publishState(.paused)
            Task {
                await sendLiveSnapshot(
                    stateOverride: .paused,
                    force: true
                )
            }
        case .ended:
            publishState(.ending)
            Task {
                await sendLiveSnapshot(
                    stateOverride: .ending,
                    force: true
                )
            }
            finishWorkout(at: date)
        default:
            break
        }
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        fail(error)
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        for payload in data {
            guard let command = try? JSONDecoder().decode(
                WatchWorkoutMirrorCommand.self,
                from: payload
            ) else {
                continue
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

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

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(
        _ workoutBuilder: HKLiveWorkoutBuilder
    ) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        updateStatistics(collectedTypes, builder: workoutBuilder)
    }
}

extension WatchWorkoutManager: CLLocationManagerDelegate {
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let filtered = locations.filter {
            $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50
        }

        guard !filtered.isEmpty else { return }

        if kind == .strength {
            if let bestLocation = filtered.min(by: {
                $0.horizontalAccuracy < $1.horizontalAccuracy
            }) {
                workoutLocation = bestLocation
                attachWorkoutLocationMetadataIfPossible()
            }
            return
        }

        routeBuilder?.insertRouteData(filtered) { [weak self] success, error in
            guard let self, !success, let error else { return }
            self.publish {
                self.errorMessage = "GPS route update failed: \(error.localizedDescription)"
            }
        }

        publish {
            let startIndex = self.routePoints.count
            self.routePoints.append(
                contentsOf: filtered.enumerated().map { offset, location in
                    WatchRoutePoint(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        altitude: location.altitude,
                        sequence: startIndex + offset
                    )
                }
            )
        }
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        guard kind == .strength,
              state == .running,
              manager.authorizationStatus == .authorizedWhenInUse ||
              manager.authorizationStatus == .authorizedAlways
        else {
            return
        }

        manager.requestLocation()
    }

    private func attachWorkoutLocationMetadataIfPossible() {
        guard kind == .strength,
              !workoutLocationMetadataAttached,
              let location = workoutLocation,
              let builder = workoutBuilder
        else {
            return
        }

        workoutLocationMetadataAttached = true

        builder.addMetadata([
            ATHLTHWorkoutMetadataKey.locationLatitude:
                location.coordinate.latitude,
            ATHLTHWorkoutMetadataKey.locationLongitude:
                location.coordinate.longitude,
            ATHLTHWorkoutMetadataKey.locationHorizontalAccuracy:
                location.horizontalAccuracy
        ]) { [weak self] success, error in
            guard let self else { return }

            if !success, let error {
                self.workoutLocationMetadataAttached = false
                self.publish {
                    self.errorMessage =
                        "Workout location could not be saved: \(error.localizedDescription)"
                }
            }
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        publish {
            self.errorMessage = "Location: \(error.localizedDescription)"
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
