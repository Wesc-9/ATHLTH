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
    var runEnvironment: RunEnvironment? = nil
    var treadmillInclinePercent: Double? = nil
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
    @Published private(set) var liveViewIsVisible = false
    @Published private(set) var isUserMinimized = false
    @Published private(set) var message: String?
    @Published private(set) var saving = false
    @Published private(set) var automaticPauseActive = false
    @Published private(set) var completionStartedWorkout: PhoneWorkout?
    @Published private(set) var lastCompletedWorkout: PhoneWorkout?
    @Published private(set) var recoveredWorkoutLastCheckpoint:
        Date?
    @Published private(set)
    var lastRouteCompletion: PhoneRouteCompletionSummary?

    private let staleRecoveryInterval:
        TimeInterval = 12 * 60 * 60

    var hasRecoveredActiveWorkout: Bool {
        active != nil &&
        recoveredWorkoutLastCheckpoint != nil
    }

    var recoveredActiveWorkoutNeedsReview: Bool {
        guard active != nil,
              let recoveredWorkoutLastCheckpoint
        else {
            return false
        }

        return Date()
            .timeIntervalSince(
                recoveredWorkoutLastCheckpoint
            ) >= staleRecoveryInterval
    }

    var recoveredActiveWorkoutReferenceDate: Date? {
        recoveredWorkoutLastCheckpoint
    }
    private var accountID: UUID?
    private var pendingWalking: Bool?
    private var pendingRunEnvironment: RunEnvironment = .outdoor
    private var pendingTreadmillInclinePercent: Double?
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
    private var ghostFinalPhaseAnnounced = false
    private var ghostOpponentName: String?
    private var lastLiveGhostConnectionText: String?
    private var lastActiveCheckpointWriteAt: Date?
    private var livePresentationRetryTask: Task<Void, Never>?
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
        pendingRunEnvironment = .outdoor
        pendingTreadmillInclinePercent = nil
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
        if let active,
           active.end != nil ||
            history.contains(
                where: { $0.id == active.id }
            ) {
            self.active = nil
        }

        recoveredWorkoutLastCheckpoint =
            active?.lastCheckpoint

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
        isUserMinimized = active != nil
        if let active {
            message =
                recoveredActiveWorkoutNeedsReview
                    ? ATHLTHLocalization.choose(
                        english:
                            "An unfinished \(active.walking ? "walk" : "run") was recovered. Review it before starting another workout.",
                        norwegian:
                            "En uferdig \(active.walking ? "gåtur" : "løpeøkt") ble gjenopprettet. Se gjennom den før du starter en ny økt."
                    )
                    : ATHLTHLocalization.choose(
                        english:
                            "Recovered workout paused at the last saved checkpoint. Resume when you are ready.",
                        norwegian:
                            "En uferdig økt ble gjenopprettet og satt på pause. Fortsett når du er klar."
                    )
        } else {
            message = nil
        }
        lastActiveCheckpointWriteAt = nil
    }

    func start(
        walking: Bool,
        route: TrainingRoute? = nil,
        title: String? = nil,
        environment: RunEnvironment = .outdoor,
        treadmillInclinePercent: Double? = nil,
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

        // If a workout is already active, treat this as a request to return
        // to its live screen. For a brand-new workout, defer presentation
        // until after the workout exists and the launch sheet has had time
        // to dismiss. Presenting a full-screen cover while SwiftUI is still
        // dismissing the quick-start sheet can otherwise be dropped.
        if active != nil {
            isUserMinimized = false
            showingWorkout = true
            return
        }

        pendingWalking = walking
        pendingRunEnvironment = environment
        pendingTreadmillInclinePercent =
            environment == .treadmill
                ? min(
                    max(treadmillInclinePercent ?? 0, 0),
                    20
                )
                : nil
        pendingRoute =
            environment == .outdoor
                ? route
                : nil
        pendingWorkoutTitle = title
        pendingAudioCoach = audioCoach
        pendingStructuredWorkout = structuredWorkout
        pendingRouteAlerts = routeAlerts
        pendingGhostAudio = ghostUpdates
        pendingAutoPauseEnabled =
            autoPauseEnabled

        if environment == .treadmill {
            beginIfAuthorized()
        } else if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            beginIfAuthorized()
        }
    }

    private func beginIfAuthorized() {
        guard let walking = pendingWalking else { return }
        let environment = pendingRunEnvironment

        if environment == .outdoor,
           manager.authorizationStatus != .authorizedAlways,
           manager.authorizationStatus != .authorizedWhenInUse {
            message = "Allow location access in iPhone Settings to record an outdoor workout."
            return
        }

        let treadmillInclinePercent =
            pendingTreadmillInclinePercent
        let route =
            environment == .outdoor
                ? pendingRoute
                : nil
        let workoutTitle = pendingWorkoutTitle
        let audioCoach = pendingAudioCoach
        let structuredWorkout =
            pendingStructuredWorkout
        let routeAlerts =
            pendingRouteAlerts ?? .standard
        let ghostUpdates =
            pendingGhostAudio
        let autoPauseEnabled =
            environment == .outdoor &&
            pendingAutoPauseEnabled

        pendingWalking = nil
        pendingRunEnvironment = .outdoor
        pendingTreadmillInclinePercent = nil
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
        recoveredWorkoutLastCheckpoint = nil
        active = PhoneWorkout(
            walking: walking,
            start: now,
            resumedAt: now,
            lastCheckpoint: now,
            pauses: [],
            autoPauseEnabled:
                autoPauseEnabled,
            runEnvironment:
                environment,
            treadmillInclinePercent:
                treadmillInclinePercent,
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

        requestLiveWorkoutPresentationAfterLaunch()

        lastLocation = nil
        automaticPauseActive = false
        autoPauseDetector.reset(
            enabled: autoPauseEnabled
        )

        if environment == .outdoor {
            message = "Waiting for a reliable GPS signal. Keep your iPhone with you."
            manager.distanceFilter =
                autoPauseEnabled ? 1 : 5
            manager.allowsBackgroundLocationUpdates = true
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            manager.distanceFilter = 5
            message = ATHLTHLocalization.format(
                english: "Treadmill run · %.1f%% incline",
                norwegian: "Tredemølle · %.1f%% stigning",
                treadmillInclinePercent ?? 0
            )
        }
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

    private func requestLiveWorkoutPresentationAfterLaunch() {
        livePresentationRetryTask?.cancel()
        isUserMinimized = false

        // The live workout is rendered as a root overlay rather than a second
        // modal presentation. It can therefore become visible immediately
        // even while the quick-start sheet is finishing its dismissal.
        showingWorkout = true
    }

    func presentWorkout() {
        guard active != nil else { return }
        livePresentationRetryTask?.cancel()
        isUserMinimized = false
        showingWorkout = true
    }

    func minimizeWorkout() {
        livePresentationRetryTask?.cancel()
        isUserMinimized = true
        showingWorkout = false
    }

    func discardActiveWorkout() {
        guard active != nil else {
            return
        }

        pause()
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.distanceFilter = 5
        active = nil
        recoveredWorkoutLastCheckpoint = nil
        showingWorkout = false
        liveViewIsVisible = false
        isUserMinimized = false
        livePresentationRetryTask?.cancel()
        automaticPauseActive = false
        autoPauseDetector.reset(enabled: false)
        resetRouteRuntime()
        message = ATHLTHLocalization.choose(
            english: "Unfinished workout discarded.",
            norwegian: "Uferdig økt forkastet."
        )
        persistActiveCheckpoint(force: true)
    }

    func setTreadmillInclinePercent(
        _ percent: Double
    ) {
        guard var workout = active,
              workout.runEnvironment ==
                .treadmill
        else {
            return
        }

        let value =
            min(
                max(percent, 0),
                20
            )

        workout.treadmillInclinePercent =
            value
        workout.lastCheckpoint = Date()
        active = workout

        message =
            ATHLTHLocalization.format(
                english:
                    "Treadmill · %.1f%% incline",
                norwegian:
                    "Tredemølle · %.1f%% stigning",
                value
            )

        persistActiveCheckpoint(
            force: true
        )
        syncLiveActivity()
    }

    func liveViewDidAppear() {
        liveViewIsVisible = true
        isUserMinimized = false
        livePresentationRetryTask?.cancel()
    }

    func liveViewDidDisappear() {
        liveViewIsVisible = false
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

        let environment =
            workout.runEnvironment ?? .outdoor

        if environment == .outdoor,
           manager.authorizationStatus != .authorizedAlways,
           manager.authorizationStatus != .authorizedWhenInUse {
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
        recoveredWorkoutLastCheckpoint = nil
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

        if environment == .outdoor {
            manager.allowsBackgroundLocationUpdates = true
            manager.startUpdatingLocation()
            message = nil
        } else {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            message = ATHLTHLocalization.format(
                english: "Treadmill run · %.1f%% incline",
                norwegian: "Tredemølle · %.1f%% stigning",
                workout.treadmillInclinePercent ?? 0
            )
        }
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

        let recoveryEnd =
            recoveredWorkoutLastCheckpoint
        workout.end =
            max(
                recoveryEnd ?? Date(),
                workout.start
            )
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
        recoveredWorkoutLastCheckpoint = nil
        showingWorkout = false
        liveViewIsVisible = false
        isUserMinimized = false
        livePresentationRetryTask?.cancel()
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
        let isIndoor =
            workout.runEnvironment == .treadmill
        configuration.locationType =
            isIndoor ? .indoor : .outdoor

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
                    HKMetadataKeyIndoorWorkout: isIndoor
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
            ghostOpponentName ??
            title ??
            "Ghost"
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

        ghostOpponentName =
            title.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
                ? nil
                : title

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

    func configureGhostOpponentName(
        _ name: String?
    ) {
        let trimmed =
            name?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        ghostOpponentName =
            trimmed?.isEmpty == false
                ? trimmed
                : nil
    }

    func applyLiveGhostConnectionState(
        opponentName: String,
        state: String,
        configuration:
            WatchGhostRaceAudioConfiguration
    ) {
        let normalized =
            state.uppercased()

        guard configuration.enabled,
              configuration
                .shouldAnnounceLiveConnectionChanges,
              active != nil
        else {
            lastLiveGhostConnectionText =
                normalized
            return
        }

        let previous =
            lastLiveGhostConnectionText
        lastLiveGhostConnectionText =
            normalized

        guard let previous,
              previous != normalized
        else {
            return
        }

        let name =
            opponentName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let resolvedName =
            name.isEmpty
                ? ATHLTHLocalization.choose(
                    english: "your opponent",
                    norwegian: "motstanderen"
                )
                : name

        if normalized == "LIVE",
           previous != "LIVE" {
            deliverPhoneGuidanceAlert(
                english:
                    "\(resolvedName) is live again.",
                norwegian:
                    "\(resolvedName) er live igjen.",
                delivery:
                    configuration
                        .resolvedImportantLeadChangeDelivery,
                haptic: .success,
                priority: .ghostImportant,
                coachConfiguration:
                    active?
                        .audioCoachConfiguration
            )
        } else if previous == "LIVE",
                  normalized != "LIVE" {
            deliverPhoneGuidanceAlert(
                english:
                    "Live connection to \(resolvedName) is interrupted.",
                norwegian:
                    "Live-tilkoblingen til \(resolvedName) er avbrutt.",
                delivery:
                    configuration
                        .resolvedImportantLeadChangeDelivery,
                haptic: .warning,
                priority: .ghostImportant,
                coachConfiguration:
                    active?
                        .audioCoachConfiguration
            )
        }
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
        ghostFinalPhaseAnnounced = false
        ghostOpponentName = nil
        lastLiveGhostConnectionText = nil

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

        var finalPhaseRemainingMeters:
            Double?

        if configuration
                .shouldAnnounceFinalPhase,
           !ghostFinalPhaseAnnounced,
           let totalDistance =
                workout
                    .plannedRouteDistanceKilometers
                    .map({
                        max(
                            $0 * 1_000,
                            0
                        )
                    }),
           totalDistance > 0 {
            let remaining =
                max(
                    totalDistance -
                        workout.distanceMeters,
                    0
                )

            if remaining > 0 &&
                remaining <=
                    configuration
                        .resolvedFinalPhaseStartMeters {
                ghostFinalPhaseAnnounced =
                    true
                finalPhaseRemainingMeters =
                    configuration
                        .resolvedFinalPhaseStartMeters
            }
        }

        if periodic ||
            finalPhaseRemainingMeters != nil {
            deliverGhostUpdate(
                distanceDelta: distanceDelta,
                timeDelta: timeDelta,
                delivery:
                    configuration
                        .resolvedPeriodicDelivery,
                priority:
                    .ghostPeriodic,
                workout: workout,
                finalPhaseRemainingMeters:
                    finalPhaseRemainingMeters
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

        guard (
            configuration
                .announceLeadChanges ||
            configuration
                .shouldAnnounceOvertakes
        ),
              elapsed >= 20
        else {
            return
        }

        let currentSign =
            ghostLeadSign(distanceDelta)
        let signChanged =
            currentSign != 0 &&
            lastGhostLeadSign != 0 &&
            currentSign != lastGhostLeadSign &&
            abs(distanceDelta) >=
                configuration
                    .resolvedLeadFlipThresholdMeters
        let change =
            lastGhostAnnouncedLeadMeters.map {
                abs(distanceDelta - $0)
            } ?? 0
        let movedEnough =
            configuration
                .announceLeadChanges &&
            change >=
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
                change >=
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
            if lastGhostAnnouncedLeadMeters ==
                nil {
                lastGhostAnnouncedLeadMeters =
                    distanceDelta
                lastGhostLeadSign =
                    currentSign
            }
            return
        }

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
            workout: workout,
            finalPhaseRemainingMeters:
                nil
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
        workout: PhoneWorkout,
        finalPhaseRemainingMeters:
            Double?
    ) {
        let meters =
            abs(distanceDelta)
        let configuration =
            workout
                .ghostAudioConfiguration ??
            .standard
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
            ghostOpponentName?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        let hasPerson =
            opponent?.isEmpty == false

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

        if meters < 8 {
            if let opponent,
               hasPerson {
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
            if let opponent,
               hasPerson {
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
            if let opponent,
               hasPerson {
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

        deliverPhoneGuidanceAlert(
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
                    : .warning,
            priority: priority,
            coachConfiguration:
                workout.audioCoachConfiguration
        )
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
            try ATHLTHSpokenAudioSession
                .activate(
                    duckOtherAudio:
                        configuration
                            .shouldDuckOtherAudio
                )
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

        ATHLTHSpokenAudioSession
            .deactivate()
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

            ATHLTHSpokenAudioSession
                .deactivate()
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

            ATHLTHSpokenAudioSession
                .deactivate()
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
