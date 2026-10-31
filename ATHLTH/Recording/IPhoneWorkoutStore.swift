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

/// Manually entered treadmill belt speed. Elapsed workout time excludes pauses;
/// entries are historical observations, not treadmill control commands.
struct PhoneTreadmillSpeedEntry: Codable, Hashable {
    let activeElapsedSeconds: TimeInterval
    let kilometersPerHour: Double
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
    /// Set only after an athlete explicitly confirms an indoor venue mid-run.
    /// Optional keeps saved workouts from prior releases compatible.
    var indoorVenue: ATHLTHIndoorRunVenue? = nil
    var indoorPromptedThisSession: Bool? = nil
    var indoorPromptPending: Bool? = nil
    var gpsDistanceBeforeIndoorSwitchMeters: Double? = nil
    var indoorSwitchActiveSeconds: TimeInterval? = nil
    var treadmillInclinePercent: Double? = nil
    var distanceMeters: Double = 0
    // Optional for compatibility with workouts from earlier builds.
    var treadmillSpeedKilometersPerHour: Double? = nil
    var treadmillDistanceElapsedSeconds: TimeInterval? = nil
    /// Nil for workouts recorded before this feature. Entries are kept with
    /// phoneHistory so future coaching can refer to verified manual inputs.
    var treadmillSpeedHistory: [PhoneTreadmillSpeedEntry]? = nil

    var averageLoggedTreadmillSpeedKilometersPerHour: Double? {
        guard runEnvironment == .treadmill,
              let speedHistory = treadmillSpeedHistory, !speedHistory.isEmpty else { return nil }
        let sorted = speedHistory.sorted { $0.activeElapsedSeconds < $1.activeElapsedSeconds }
        let total = max(elapsed(at: end ?? Date()), 0)
        var weightedDistance = 0.0
        var measuredSeconds = 0.0
        for (index, point) in sorted.enumerated() {
            let start = max(point.activeElapsedSeconds, 0)
            let finish = min(max(
                index + 1 < sorted.count ? sorted[index + 1].activeElapsedSeconds : total,
                start
            ), total)
            let interval = max(finish - start, 0)
            guard point.kilometersPerHour > 0, point.kilometersPerHour <= 30,
                  point.kilometersPerHour.isFinite else { continue }
            measuredSeconds += interval
            weightedDistance += interval * point.kilometersPerHour
        }
        guard measuredSeconds >= 30 else { return nil }
        return weightedDistance / measuredSeconds
    }
    var points: [PhoneRoutePoint] = []
    var healthID: UUID?
    // Explicit plan origin, optional to preserve previous history.
    var plannedPlanID: UUID? = nil
    var plannedSessionID: UUID? = nil
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
    var routeNearestPointIndex: Int? = nil
    var routeCurrentCourseDegrees: Double? = nil
    var returningToRouteStart: Bool? = nil
    var routeLegDistanceOffsetMeters: Double? = nil
    var ghostDisabledDuringWorkout: Bool? = nil
    var currentPaceSecondsPerKilometer: TimeInterval? = nil

    // The same structured running model is used by Apple Watch.
    var structuredRunningWorkout: WatchRunningWorkoutTransfer? = nil
    var structuredStepIndex: Int? = nil
    var structuredStepStartElapsedTime: TimeInterval? = nil
    var structuredStepStartDistanceMeters: Double? = nil
    var structuredWorkoutComplete: Bool? = nil
    /// Paused between finishing the warm-up and deliberately starting main.
    var awaitingMainStart: Bool? = nil
    // Recorded active-time and distance at each completed structured step.
    // Partial runs retain this diagnostic data but never enter progression.
    var recordedRunningSteps: [ATHLTHRecordedRunningStep]? = nil
    /// Per-minute step evidence, including partial final slices.
    var recordedRunningMinutes: [ATHLTHRecordedRunningMinute]? = nil

    var audioCoachConfiguration:
        WatchAudioCoachConfiguration? = nil
    var routeAlertConfiguration:
        WatchRouteAlertConfiguration? = nil
    var ghostAudioConfiguration:
        WatchGhostRaceAudioConfiguration? = nil
    var ghostOpponentName: String? = nil
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
    /// Integrate entered belt speed over active time only, never GPS or pause time.
    mutating func advanceTreadmillDistance(at date: Date) {
        guard runEnvironment == .treadmill else { return }
        let elapsed = self.elapsed(at: date)
        guard elapsed.isFinite else { return }
        defer { treadmillDistanceElapsedSeconds = elapsed }
        guard let previous = treadmillDistanceElapsedSeconds,
              let speed = treadmillSpeedKilometersPerHour,
              speed.isFinite, (0...30).contains(speed), elapsed >= previous
        else { return }
        distanceMeters += speed / 3.6 * (elapsed - previous)
    }

    mutating func setTreadmillSpeed(_ speed: Double, at date: Date) {
        guard runEnvironment == .treadmill,
              speed.isFinite, (0...30).contains(speed) else { return }
        advanceTreadmillDistance(at: date)
        treadmillSpeedKilometersPerHour = speed
        treadmillDistanceElapsedSeconds = elapsed(at: date)
        let elapsed = elapsed(at: date)
        if treadmillSpeedHistory?.last?.kilometersPerHour != speed {
            var samples = treadmillSpeedHistory ?? []
            samples.append(PhoneTreadmillSpeedEntry(
                activeElapsedSeconds: elapsed,
                kilometersPerHour: speed
            ))
            treadmillSpeedHistory = samples
        }
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
    @Published private(set) var treadmillInclineOverrides:
        [UUID: Double] = [:]
    @Published var showingWorkout = false
    @Published private(set) var liveViewIsVisible = false
    @Published private(set) var isUserMinimized = false
    @Published private(set) var message: String?
    @Published private(set) var saving = false
    @Published private(set) var automaticPauseActive = false
    /// A question, not an automatic classification. A manual choice is always available.
    @Published private(set) var indoorSuggestionAvailable = false
    private var indoorFirstReliableFix: Date?
    private var indoorLastReliableFix: Date?
    private var indoorAcceptedFixCount = 0
    /// Temporary voice mute: does not stop recording or critical haptics.
    @Published private(set) var coachSpeechPaused = false
    @Published private(set) var lastCoachMessage: String?
    private var coachReplayMemory = ATHLTHCoachReplayMemory()

    var canReplayLastCoachMessage: Bool {
        active?.audioCoachConfiguration?.enabled == true &&
        !coachSpeechPaused &&
        coachReplayMemory.replayableText() != nil
    }
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

    /// Live Ghost needs an immediately authorized outdoor recorder before
    /// both athletes agree to a synchronized start. A deferred permission
    /// dialog would otherwise cause one runner to start late.
    var canStartSynchronizedOutdoorWorkout: Bool {
        guard accountID != nil, !saving else { return false }
        return manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse
    }

    func requestLiveGhostLocationPermissionIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
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
    private var pendingPlannedPlanID: UUID?
    private var pendingPlannedSessionID: UUID?
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
    private var coachPaceSampleAt: Date?
    private var lastGoalEncouragementAt: Date?
    private var autoPauseDetector =
        OutdoorAutoPauseDetector()
    private var plannedRouteLocations: [CLLocation] = []
    private var plannedRouteCumulativeMeters: [Double] = []
    private var plannedRouteGeometryMeters: Double = 0

    private let speechSynthesizer =
        AVSpeechSynthesizer()
    private let azureCoachSpeech = ATHLTHAzureWorkoutSpeech()
    private let audioOwner = "phone-workout-\(UUID().uuidString)"
    private var localSpeechWatchdog: Task<Void, Never>?
    private var guidancePriorityGate =
        ATHLTHGuidancePriorityGate()
    private var coachEventLedger = ATHLTHCoachEventLedger()
    private var coachCueQueue = ATHLTHCoachCueQueue()
    private var nextDistanceAnnouncementMeters: Double?
    private var nextTimeAnnouncementSeconds: TimeInterval?
    private var customAudioCoachLastSlots: [UUID: Int] = [:]
    private var nextFuelAnnouncementSeconds: TimeInterval?
    private var offRouteStartedAt: Date?
    private var lastOffRouteAlertAt: Date?
    private var lastSpokenRouteTurnAt: Date?
    private var lastSpokenRouteTurnIndex: Int?
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
    private var treadmillTickTask: Task<Void, Never>?
    private var structuredTickTask: Task<Void, Never>?
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
        treadmillTickTask?.cancel()
        treadmillTickTask = nil
        structuredTickTask?.cancel()
        structuredTickTask = nil
        manager.stopUpdatingLocation()
        resetIndoorProbe()
        accountID = userID
        pendingWalking = nil
        pendingPlannedPlanID = nil
        pendingPlannedSessionID = nil
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
            workout.advanceTreadmillDistance(at: workout.lastCheckpoint)
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
        if let userID,
           !UserDefaults.standard.bool(forKey: AccountLocalStorage.key("deleted", userID: userID)),
           let completed = PhoneWorkoutCompletionJournal.read(userID: userID),
           !history.contains(where: { $0.id == completed.id }) {
            history.insert(completed, at: 0)
            history.sort { $0.start > $1.start }
            persistHistory()
        }
        if let userID,
           !UserDefaults.standard.bool(
             forKey: AccountLocalStorage.key("deleted", userID: userID)
           ) {
            ATHLTHRunningPerformanceHistory.backfillPhoneHistory(
                history, userID: userID
            )
        }
        treadmillInclineOverrides =
            userID.flatMap {
                AccountLocalStorage.read(
                    [UUID: Double].self,
                    name: "treadmillInclineOverrides",
                    userID: $0
                )
            } ?? [:]
        if let active,
           active.end != nil ||
            history.contains(
                where: { $0.id == active.id }
            ) {
            self.active = nil
            persistActiveCheckpoint(force: true)
        }

        recoveredWorkoutLastCheckpoint =
            active?.lastCheckpoint
        indoorSuggestionAvailable = active?.indoorPromptPending == true

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
            ghostOpponentName =
                active.ghostOpponentName
            guidancePriorityGate.reset()
            coachEventLedger.reset()
            coachCueQueue.reset()
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
        autoPauseEnabled: Bool = false,
        plannedPlanID: UUID? = nil,
        plannedSessionID: UUID? = nil
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
        pendingPlannedPlanID = plannedPlanID
        pendingPlannedSessionID = plannedSessionID
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

        if environment != .outdoor {
            // Indoor running and treadmill do not require location permission.
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
        let plannedPlanID = pendingPlannedPlanID
        let plannedSessionID = pendingPlannedSessionID
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
        pendingPlannedPlanID = nil
        pendingPlannedSessionID = nil
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
        coachEventLedger.reset()
        coachCueQueue.reset()
        coachSpeechPaused = false
        coachReplayMemory.reset()
        lastCoachMessage = nil

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
            plannedPlanID: plannedPlanID,
            plannedSessionID: plannedSessionID,
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
        resetIndoorProbe()
        coachPaceSampleAt = nil
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
        startTreadmillTicksIfNeeded()
        startStructuredTicksIfNeeded()
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

        if environment == .treadmill, audioCoach?.enabled == true,
           let prior = lastTreadmillSpeedReference {
            let speed = prior.speed
            speak(
                localizedCoachPhrase(
                    english: String(format:
                        "Your previous manually logged treadmill average was %.1f kilometers per hour. Use it only as a reference and adjust to today's effort.", speed),
                    norwegian: String(format:
                        "Forrige registrerte møllegjennomsnitt var %.1f kilometer i timen. Bruk det som referanse og tilpass etter dagsformen.", speed),
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
        guard let workoutID = active?.id else { return }
        livePresentationRetryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled, let self,
                      self.active?.id == workoutID,
                      !self.isUserMinimized,
                      !self.liveViewIsVisible
                else { return }
                guard UIApplication.shared.applicationState == .active else { return }
                // Refresh the root overlay if launch coincided with another
                // sheet or the previous Watch live screen being dismissed.
                self.showingWorkout = false
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(70))
                guard !Task.isCancelled,
                      self.active?.id == workoutID,
                      !self.isUserMinimized else { return }
                self.showingWorkout = true
            }
        }
    }

    func restoreLivePresentationIfNeeded() {
        guard active != nil, !isUserMinimized, !liveViewIsVisible else { return }
        requestLiveWorkoutPresentationAfterLaunch()
    }

    func presentWorkout() {
        guard active != nil else { return }
        requestLiveWorkoutPresentationAfterLaunch()
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
        treadmillTickTask?.cancel()
        treadmillTickTask = nil
        structuredTickTask?.cancel()
        structuredTickTask = nil
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

    /// Live overrides affect only the current iPhone workout.
    /// Start at the next milestone, not a threshold already passed.
    func updateAudioCoachDuringWorkout(
        _ configuration: WatchAudioCoachConfiguration
    ) {
        guard var workout = active else { return }

        let wasEnabled =
            workout.audioCoachConfiguration?.enabled == true
        let now = Date()
        workout.audioCoachConfiguration = configuration
        workout.lastCheckpoint = now
        active = workout

        if !configuration.enabled {
            coachSpeechPaused = false
        }
        if configuration.enabled {
            nextDistanceAnnouncementMeters =
                configuration.distanceIntervalMeters.flatMap { interval in
                    guard interval > 0 else { return nil }
                    return (floor(workout.distanceMeters / interval) + 1) * interval
                }
            nextTimeAnnouncementSeconds =
                configuration.timeIntervalSeconds.flatMap { interval in
                    guard interval > 0 else { return nil }
                    return (floor(workout.elapsed(at: now) / interval) + 1) * interval
                }
            nextFuelAnnouncementSeconds = ATHLTHFuelVoicePrompt.nextDue(
                after: workout.elapsed(at: now),
                config: configuration
            )
            customAudioCoachLastSlots = ATHLTHAudioCoachRuleDelivery.initialSlots(
                rules: configuration.customRules ?? [],
                distanceMeters: workout.distanceMeters,
                elapsedSeconds: workout.elapsed(at: now)
            )
        } else {
            resetCoachThresholds(configuration: nil)
            deactivateCoachAudioSession()
            guidancePriorityGate.reset()
            coachCueQueue.reset()
        }

        persistActiveCheckpoint(force: true)
        syncLiveActivity()

        if configuration.enabled && !wasEnabled {
            speak(
                localizedCoachPhrase(
                    english: "Audio Coach is on.",
                    norwegian: "Audio Coach er på.",
                    configuration: configuration
                ),
                configuration: configuration,
                priority: .structuredStep
            )
        }
    }

    /// Silences spoken coaching during this workout only, without changing
    /// the persisted workout configuration, cadence, route or haptic alerts.
    func setCoachSpeechPaused(_ paused: Bool) {
        guard active?.audioCoachConfiguration?.enabled == true else {
            coachSpeechPaused = false
            return
        }
        guard coachSpeechPaused != paused else { return }
        coachSpeechPaused = paused
        coachCueQueue.reset()
        guidancePriorityGate.reset()
        if paused {
            deactivateCoachAudioSession()
        }
    }

    /// Returns only fresh live metrics on a requested AI tool call.
    /// Phone-only workouts do not currently provide a verified live HR feed.
    func liveAICoachStatus(now: Date = Date()) -> ATHLTHLiveCoachWorkoutStatus {
        guard let workout = active else { return .unavailable }
        let elapsed = workout.elapsed(at: now)
        let running = workout.resumedAt != nil
        let stepIndex = workout.structuredStepIndex ?? 0
        let steps = workout.structuredRunningWorkout?.steps ?? []
        let activeStep: WatchRunningWorkoutStep? =
            workout.structuredWorkoutComplete != true &&
            steps.indices.contains(stepIndex) ? steps[stepIndex] : nil
        let durationRemaining: Double?
        let distanceRemaining: Double?
        if let activeStep {
            switch activeStep.measure {
            case .time:
                durationRemaining = activeStep.durationSeconds.map {
                    max(0, $0 - (elapsed -
                        (workout.structuredStepStartElapsedTime ?? 0)))
                }
                distanceRemaining = nil
            case .distance:
                durationRemaining = nil
                distanceRemaining = activeStep.distanceMeters.map {
                    max(0, $0 - (workout.distanceMeters -
                        (workout.structuredStepStartDistanceMeters ?? 0)))
                }
            case .open:
                durationRemaining = nil
                distanceRemaining = nil
            }
        } else {
            durationRemaining = nil
            distanceRemaining = nil
        }
        return ATHLTHLiveCoachWorkoutStatus(
            availability: "available",
            activity: workout.walking ? "walking" : "running",
            state: running ? "running" : "paused",
            elapsedSeconds: ATHLTHLiveCoachWorkoutStatus.positiveInteger(elapsed),
            distanceMeters: ATHLTHLiveCoachWorkoutStatus.positiveInteger(workout.distanceMeters),
            paceSecondsPerKilometer: running &&
                ATHLTHCoachSensorFreshness.validPace(
                    workout.currentPaceSecondsPerKilometer,
                    sampledAt: coachPaceSampleAt, now: now
                ) ? ATHLTHLiveCoachWorkoutStatus.positiveInteger(
                    workout.currentPaceSecondsPerKilometer
                ) : nil,
            heartRateBPM: nil,
            currentStep: activeStep?.title,
            nextStep: activeStep != nil && steps.indices.contains(stepIndex + 1)
                ? steps[stepIndex + 1].title : nil,
            stepNumber: activeStep == nil ? nil : stepIndex + 1,
            totalSteps: activeStep == nil ? nil : steps.count,
            stepRemainingSeconds: ATHLTHLiveCoachWorkoutStatus.positiveInteger(durationRemaining),
            stepRemainingMeters: ATHLTHLiveCoachWorkoutStatus.positiveInteger(distanceRemaining),
            targetPaceMinimumSecondsPerKilometer: ATHLTHLiveCoachWorkoutStatus.positiveInteger(
                activeStep?.targetPaceMinSecondsPerKilometer
            ),
            targetPaceMaximumSecondsPerKilometer: ATHLTHLiveCoachWorkoutStatus.positiveInteger(
                activeStep?.targetPaceMaxSecondsPerKilometer
            )
        )
    }

    /// One-off status, read from the active recorder. No threshold reset.
    func announceCoachStatusNow() {
        guard !coachSpeechPaused,
              let workout = active,
              let configuration = workout.audioCoachConfiguration,
              configuration.enabled
        else { return }

        let norwegian =
            localizedCoachPhrase(
                english: "en",
                norwegian: "no",
                configuration: configuration
            ) == "no"
        let elapsed = workout.elapsed(at: Date())
        var parts: [String] = []

        if configuration.announceDistance || configuration.announceAveragePace {
            parts.append(
                String(
                    format: norwegian ? "Distanse %.2f kilometer" : "Distance %.2f kilometers",
                    workout.distanceMeters / 1_000
                )
            )
        }
        if configuration.announceElapsedTime || parts.isEmpty {
            parts.append(
                (norwegian ? "Tid " : "Time ") +
                durationPhrase(elapsed, norwegian: norwegian)
            )
        }
        if configuration.announceAveragePace,
           workout.distanceMeters >= 100,
           elapsed > 0 {
            let pace = elapsed / (workout.distanceMeters / 1_000)
            parts.append(
                (norwegian ? "Gjennomsnittstempo " : "Average pace ") +
                pacePhrase(pace, norwegian: norwegian)
            )
        }
        if configuration.announceRemainingRouteDistance,
           let remaining = workout.routeRemainingMeters,
           remaining.isFinite,
           remaining >= 0 {
            parts.append(
                String(
                    format: norwegian ? "%.1f kilometer igjen" : "%.1f kilometers remaining",
                    remaining / 1_000
                )
            )
        }
        guard !parts.isEmpty else { return }
        speak(
            parts.joined(separator: ". "),
            configuration: configuration,
            priority: .structuredStep,
            event: ATHLTHCoachEvent(
                kind: .manualStatus,
                key: UUID().uuidString,
                priority: .structuredStep,
                validFor: 8
            )
        )
    }

    /// Explicit replay uses this workout's current voice settings but
    /// never re-records the replay or moves automatic cue thresholds.
    func replayLastCoachMessage() {
        guard canReplayLastCoachMessage,
              let phrase = coachReplayMemory.replayableText(),
              let configuration = active?.audioCoachConfiguration
        else { return }

        speak(
            phrase,
            configuration: configuration,
            priority: .structuredStep,
            rememberForReplay: false
        )
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

    func treadmillInclinePercent(
        for workoutID: UUID
    ) -> Double? {
        if let local =
                history.first(
                    where: {
                        $0.id == workoutID ||
                        $0.healthID == workoutID
                    }
                ),
           local.runEnvironment == .treadmill {
            return local.treadmillInclinePercent ??
                treadmillInclineOverrides[
                    workoutID
                ]
        }

        return treadmillInclineOverrides[
            workoutID
        ]
    }

    func setCompletedTreadmillInclinePercent(
        _ percent: Double,
        workoutID: UUID
    ) {
        let value =
            min(
                max(
                    (percent * 2).rounded() / 2,
                    0
                ),
                20
            )

        treadmillInclineOverrides[
            workoutID
        ] = value

        if let index =
                history.firstIndex(
                    where: {
                        $0.id == workoutID ||
                        $0.healthID == workoutID
                    }
                ) {
            history[index]
                .runEnvironment =
                .treadmill
            history[index]
                .treadmillInclinePercent =
                value

            treadmillInclineOverrides[
                history[index].id
            ] = value

            if let healthID =
                    history[index]
                        .healthID {
                treadmillInclineOverrides[
                    healthID
                ] = value
            }

            if lastCompletedWorkout?
                .id ==
                history[index].id {
                lastCompletedWorkout =
                    history[index]
            }

            persistHistory()
        }

        persistTreadmillInclineOverrides()

        message =
            ATHLTHLocalization.format(
                english:
                    "Treadmill incline updated to %.1f%%.",
                norwegian:
                    "Stigning på tredemølle oppdatert til %.1f%%.",
                value
            )
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
        coachPaceSampleAt = nil
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

        workout.advanceTreadmillDistance(at: now)
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
        coachPaceSampleAt = nil
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
        workout.treadmillDistanceElapsedSeconds = workout.elapsed(at: now)
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
        coachPaceSampleAt = nil

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
        startTreadmillTicksIfNeeded()
        startStructuredTicksIfNeeded()
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
        coachPaceSampleAt = nil
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
        coachPaceSampleAt = nil
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
        let minuteSampleEnd = workout.end ?? Date()
        recordRunningMinuteIfDue(&workout, force: true, at: minuteSampleEnd)
        // Keep the final in-progress phase in the durable result as a
        // partial step. A fully completed structured workout already records
        // its last phase at the transition.
        if let plan = workout.structuredRunningWorkout,
           workout.structuredWorkoutComplete != true,
           let index = workout.structuredStepIndex,
           plan.steps.indices.contains(index),
           !(workout.recordedRunningSteps ?? []).contains(where: { $0.index == index }) {
            let step = plan.steps[index]
            let endElapsed = workout.elapsed(at: workout.end ?? Date())
            let seconds = max(0, endElapsed -
                (workout.structuredStepStartElapsedTime ?? 0))
            let meters = max(0, workout.distanceMeters -
                (workout.structuredStepStartDistanceMeters ?? 0))
            if seconds > 0 {
                workout.recordedRunningSteps = (workout.recordedRunningSteps ?? []) + [
                    ATHLTHRecordedRunningStep(
                        index: index, title: step.title, phase: step.phase,
                        activeSeconds: seconds, distanceMeters: meters,
                        isUserReported: workout.runEnvironment == .treadmill,
                        targetPaceSecondsPerKilometer:
                            step.targetPaceMinSecondsPerKilometer,
                        targetDurationSeconds: step.durationSeconds,
                        targetHeartRateZone: step.targetHeartRateZone,
                        targetTreadmillInclinePercent:
                            step.targetTreadmillInclinePercent
                    )
                ]
            }
        }

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

        guard !UserDefaults.standard.bool(forKey: AccountLocalStorage.key("deleted", userID: userID)) else { return }
        var completedHistory = history.filter { $0.id != workout.id }
        completedHistory.insert(workout, at: 0)
        do {
            // Durable completion first; retain active state on any encoding/write failure.
            try PhoneWorkoutCompletionJournal.save(workout, userID: userID)
            try AccountLocalStorage.writeChecked(completedHistory, name: "phoneHistory", userID: userID)
        } catch {
            message = ATHLTHLocalization.choose(
                english: "Could not save the workout on this device. It remains paused; try finishing again.",
                norwegian: "Kunne ikke lagre økten på enheten. Den er fortsatt pauset; prøv å avslutte igjen."
            )
            return
        }

        syncLiveActivity(workout: workout, state: .completed)
        treadmillTickTask?.cancel()
        treadmillTickTask = nil
        structuredTickTask?.cancel()
        structuredTickTask = nil
        history = completedHistory
        active = nil
        recoveredWorkoutLastCheckpoint = nil
        showingWorkout = false
        liveViewIsVisible = false
        isUserMinimized = false
        livePresentationRetryTask?.cancel()
        automaticPauseActive = false
        autoPauseDetector.reset(enabled: false)
        resetIndoorProbe()
        manager.distanceFilter = 5
        resetRouteRuntime()
        persistActiveCheckpoint(force: true)
        // completedHistory was already encoded and written before clearing active.
        ATHLTHTrainingDataChangeSignal.post(userID: userID)

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
        guard accountID == userID else { return }

        // Emit completion only after the Health save attempt has settled so
        // downstream Goals, Challenges and the review all see the final
        // HealthKit workout identity when one is available.
        let finalWorkout = history.first(where: { $0.id == workout.id }) ?? workout
        ATHLTHRunningPerformanceHistory.savePhone(finalWorkout, userID: userID)
        lastCompletedWorkout = finalWorkout
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
            if let index = history.firstIndex(where: { $0.id == workout.id }),
               PhoneWorkoutCompletionJournal.read(userID: userID)?.id == workout.id {
                try? PhoneWorkoutCompletionJournal.save(history[index], userID: userID)
            }

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
                    HKMetadataKeyIndoorWorkout: isIndoor,
                    "ATHLTHDistanceSource": isIndoor
                        ? (workout.indoorVenue == .indoorRunning ? "unavailable" :
                            (workout.treadmillSpeedKilometersPerHour != nil
                                ? "entered_belt_speed" : "unavailable"))
                        : "gps",
                    "ATHLTHIndoorVenue": workout.indoorVenue?.rawValue ?? "not_specified",
                    "ATHLTHIndoorSwitchActiveSeconds":
                        workout.indoorSwitchActiveSeconds ?? 0,
                    "ATHLTHGPSDistanceBeforeIndoorSwitchMeters":
                        workout.gpsDistanceBeforeIndoorSwitchMeters ?? 0
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

    /// Local, user-specific reference. Never interpreted as live belt speed.
    var lastTreadmillSpeedReference: (speed: Double, date: Date)? {
        history
            .filter { $0.runEnvironment == .treadmill && $0.end != nil }
            .sorted { $0.start > $1.start }
            .compactMap { workout -> (speed: Double, date: Date)? in
                guard let speed = workout.averageLoggedTreadmillSpeedKilometersPerHour,
                      speed >= 3, speed <= 25 else { return nil }
                return (speed, workout.end ?? workout.start)
            }
            .first
    }

    /// Record user-reported treadmill pace for history/next coaching session
    /// without advancing distance or modifying the current belt-speed estimate.
    func recordTreadmillHistoricalSpeedKilometersPerHour(_ speed: Double) {
        guard var workout = active,
              workout.runEnvironment == .treadmill,
              speed.isFinite, (0...30).contains(speed) else { return }
        var points = workout.treadmillSpeedHistory ?? []
        let elapsed = workout.elapsed(at: Date())
        if points.last?.kilometersPerHour != speed ||
           (points.last?.activeElapsedSeconds ?? -1) < elapsed - 60 {
            points.append(PhoneTreadmillSpeedEntry(
                activeElapsedSeconds: elapsed,
                kilometersPerHour: speed
            ))
            workout.treadmillSpeedHistory = points
            active = workout
            checkpoint(force: true)
        }
    }

    func setTreadmillSpeedKilometersPerHour(_ speed: Double) {
        guard var workout = active, workout.runEnvironment == .treadmill,
              workout.indoorVenue != .indoorRunning,
              speed.isFinite, (0...30).contains(speed) else { return }
        workout.setTreadmillSpeed(speed, at: Date())
        active = workout
        checkpoint()
    }

    private func startStructuredTicksIfNeeded() {
        guard active?.structuredRunningWorkout?.steps.isEmpty == false,
              structuredTickTask == nil else { return }
        structuredTickTask = Task { @MainActor [weak self] in
            var lastMinuteCheckpointKey: String?
            var lastCoachTickSecond = -1
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self,
                      let current = self.active,
                      current.structuredRunningWorkout != nil else { return }
                guard current.resumedAt != nil,
                      current.structuredWorkoutComplete != true,
                      current.awaitingMainStart != true,
                      let step = self.currentStructuredStep else { continue }
                // Write a sample at each active minute even without GPS movement.
                let elapsed = current.elapsed(at: Date())
                let elapsedInStep = max(elapsed -
                    (current.structuredStepStartElapsedTime ?? 0), 0)
                let minute = Int(elapsedInStep / 60)
                let minuteKey = "\(step.id):\(minute)"
                let coachSecond = Int(elapsed)
                if coachSecond != lastCoachTickSecond {
                    lastCoachTickSecond = coachSecond
                    self.announceStructuredIntervalCues(current, elapsed: elapsed)
                }
                if minute > 0 && minuteKey != lastMinuteCheckpointKey {
                    lastMinuteCheckpointKey = minuteKey
                    self.checkpoint(force: true)
                }
                if step.phase == "cooldown" ||
                   (step.phase == "warmup" &&
                    current.structuredRunningWorkout?.autoStartMainAfterWarmup != true) {
                    continue
                }
                // Use authoritative active time, not a second timer.
                if step.measure == .time,
                   (step.phase == "warmup"
                      ? current.structuredRunningWorkout?.autoStartMainAfterWarmup == true
                      : (current.structuredRunningWorkout?.autoAdvanceTimedSteps ?? true)),
                   let duration = step.durationSeconds,
                   elapsed - (current.structuredStepStartElapsedTime ?? 0) >= duration {
                    self.checkpoint(force: true)
                }
            }
        }
    }

    private func startTreadmillTicksIfNeeded() {
        guard active?.runEnvironment == .treadmill, treadmillTickTask == nil else { return }
        treadmillTickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self,
                      self.active?.runEnvironment == .treadmill else { return }
                if self.active?.resumedAt != nil { self.checkpoint(force: false) }
            }
        }
    }

    func checkpoint(force: Bool = true) {
        guard var workout = active else { return }

        let now = Date()
        workout.advanceTreadmillDistance(at: now)
        workout.lastCheckpoint = now

        if workout.resumedAt != nil {
            recordRunningMinuteIfDue(&workout, at: now)
            evaluateStructuredWorkout(
                &workout
            )
            evaluateCoachAnnouncements(
                workout
            )
        }

        active = workout
        evaluateIndoorSuggestion(now: now)
        persistActiveCheckpoint(force: force)
        syncLiveActivity()
    }

    /// Add a timed/distance interval program to the SAME active phone
    /// recording. Never starts a second HealthKit workout or resets totals.
    /// Completed and in-flight steps remain intact when another part is
    /// queued. Start-now is allowed only when no other part is in progress.
    @discardableResult
    func appendRunningIntervalsDuringWorkout(
        _ template: RunningWorkoutTemplate,
        startNow: Bool
    ) -> Bool {
        guard var workout = active,
              !workout.walking,
              !saving,
              workout.resumedAt != nil else { return false }

        let addition = watchRunningWorkoutTransfer(from: template)
        let existing = workout.structuredRunningWorkout
        let existingComplete = workout.structuredWorkoutComplete == true
        guard ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: existing != nil && !existingComplete,
            startNow: startNow,
            steps: addition.steps
        ) else { return false }

        let priorCount = existing?.steps.count ?? 0
        if var current = existing {
            current.steps.append(contentsOf: addition.steps)
            current.sourceWorkoutID = nil
            workout.structuredRunningWorkout = current
        } else {
            workout.structuredRunningWorkout = addition
        }

        if existing == nil || existingComplete {
            workout.structuredStepIndex = priorCount
            workout.structuredStepStartElapsedTime = workout.elapsed(at: Date())
            workout.structuredStepStartDistanceMeters = workout.distanceMeters
        }
        workout.structuredWorkoutComplete = false
        active = workout
        persistActiveCheckpoint(force: true)
        startStructuredTicksIfNeeded()
        syncLiveActivity()
        return true
    }

    func advanceStructuredStepManually() {
        guard var workout = active,
              workout.resumedAt != nil,
              workout.structuredWorkoutComplete != true,
              currentStructuredStep != nil else { return }
        if workout.awaitingMainStart == true {
            // Waiting time/distance is not credited to the first interval.
            workout.structuredStepStartElapsedTime = workout.elapsed(at: Date())
            workout.structuredStepStartDistanceMeters = workout.distanceMeters
            workout.awaitingMainStart = false
            if workout.structuredRunningWorkout?.deferRouteUntilMain == true,
               workout.structuredStepIndex == 1 {
                // Warm-up distance is part of the overall recording, not the route.
                workout.routeLegDistanceOffsetMeters = workout.distanceMeters
            }
            active = workout
            persistActiveCheckpoint(force: true)
            syncLiveActivity()
            announceStructuredStepIfNeeded(prefix: "Starting")
            return
        }
        guard let step = currentStructuredStep,
              step.phase == "warmup" || step.phase == "cooldown" ||
              step.measure == .open ||
              workout.structuredRunningWorkout?.autoAdvanceTimedSteps == false
        else { return }
        evaluateStructuredWorkout(&workout, forceManualAdvance: true)
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
              let step = currentStructuredStep,
              workout.awaitingMainStart != true
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

        guard workout.ghostDisabledDuringWorkout != true else { return }
        ghostOpponentName =
            workout.ghostOpponentName ??
            ghostOpponentName

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
              !workout.walking,
              workout.ghostDisabledDuringWorkout != true
        else {
            return
        }

        ghostOpponentName =
            title.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
                ? nil
                : title
        workout.ghostOpponentName =
            ghostOpponentName

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

        if var workout = active,
           workout.ghostDisabledDuringWorkout != true {
            workout.ghostOpponentName =
                ghostOpponentName
            if ghostOpponentName != nil {
                workout.ghostRaceTitle =
                    ghostOpponentName
            }
            active = workout
            persistActiveCheckpoint(
                force: true
            )
        }
    }

    /// Leave the duellist and HealthKit session intact, but discard an
    /// expired GPS advantage. This is a display/audio reset only.
    func clearLiveGhostGap() {
        guard var workout = active,
              !workout.walking,
              workout.ghostRaceTitle != nil,
              workout.ghostDistanceDeltaMeters != nil ||
                workout.ghostTimeDeltaSeconds != nil
        else { return }

        workout.ghostDistanceDeltaMeters = nil
        workout.ghostTimeDeltaSeconds = nil
        active = workout
        persistActiveCheckpoint()
        syncLiveActivity()
    }

    func applyLiveGhostConnectionState(
        opponentName: String,
        state: String,
        configuration:
            WatchGhostRaceAudioConfiguration
    ) {
        let normalized =
            state.uppercased()
        if normalized != "LIVE" {
            clearLiveGhostGap()
        }

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
        nextFuelAnnouncementSeconds = nil
        resetRouteAlertRuntime()
        resetGhostRuntime(
            configuration: nil
        )
        guidancePriorityGate.reset()
        coachEventLedger.reset()
        coachCueQueue.reset()
        coachSpeechPaused = false
        coachReplayMemory.reset()
        lastCoachMessage = nil
        azureCoachSpeech.stop()
        speechSynthesizer.stopSpeaking(
            at: .immediate
        )
    }

    private func resetCoachThresholds(
        configuration:
            WatchAudioCoachConfiguration?
    ) {
        lastGoalEncouragementAt = nil
        customAudioCoachLastSlots = ATHLTHAudioCoachRuleDelivery.initialSlots(
            rules: configuration?.customRules ?? [],
            distanceMeters: active?.distanceMeters ?? 0,
            elapsedSeconds: active?.elapsed(at: Date()) ?? 0
        )
        guard let configuration,
              configuration.enabled
        else {
            nextDistanceAnnouncementMeters = nil
            nextTimeAnnouncementSeconds = nil
            nextFuelAnnouncementSeconds = nil
            return
        }

        nextFuelAnnouncementSeconds = ATHLTHFuelVoicePrompt.nextDue(
            after: 0,
            config: configuration
        )

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
        lastSpokenRouteTurnAt = nil
        lastSpokenRouteTurnIndex = nil
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
        guard workout.runEnvironment == .outdoor,
              let rawPace = ATHLTHRunningPace.outdoorGPS(
                  speedMetersPerSecond: location.speed,
                  isOutdoor: true
              ),
              ATHLTHCoachSensorFreshness.isFresh(
                  sampledAt: location.timestamp,
                  maximumAge:
                    ATHLTHCoachSensorFreshness.maximumPaceAge
              )
        else {
            return
        }

        coachPaceSampleAt = location.timestamp

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

    var liveRouteNavigationCue: ATHLTHRouteNavigationCue.Instruction? {
        guard let workout = active,
              let index = workout.routeNearestPointIndex,
              let coords = workout.plannedRouteCoordinates,
              let point = workout.points.last,
              let deviation = workout.routeDeviationMeters else { return nil }
        let sorted = coords.sorted { $0.sequence < $1.sequence }
        let route = sorted.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        if workout.routeAlertConfiguration?.enabled == true &&
            deviation > (workout.routeAlertConfiguration?.deviationMeters ?? 80) {
            return ATHLTHRouteNavigationCue.recovery(
                user: CLLocationCoordinate2D(
                    latitude: point.latitude, longitude: point.longitude
                ),
                courseDegrees: workout.routeCurrentCourseDegrees,
                route: route,
                nearestIndex: index,
                deviationMeters: deviation
            )
        }
        return ATHLTHRouteNavigationCue.nextTurn(route: route, nearestIndex: index)
    }

    var canRunBackToStart: Bool {
        guard let workout = active,
              !workout.walking,
              workout.runEnvironment != .treadmill,
              workout.returningToRouteStart != true,
              (workout.routeRemainingMeters ?? .infinity) <= 125,
              (workout.routeProgressPercent ?? 0) >= 85,
              (workout.routeDistanceToFinishMeters ?? .infinity) <= 100,
              let coordinates = workout.plannedRouteCoordinates,
              coordinates.count >= 2
        else { return false }
        let sorted = coordinates.sorted { $0.sequence < $1.sequence }
        guard let first = sorted.first, let last = sorted.last else {
            return false
        }
        return CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: last.latitude,
                                       longitude: last.longitude)) > 60
    }

    func startReturnToRouteStart() {
        guard canRunBackToStart, var workout = active,
              let coordinates = workout.plannedRouteCoordinates else { return }
        workout.plannedRouteCoordinates = coordinates
            .sorted { $0.sequence < $1.sequence }
            .reversed()
            .enumerated()
            .map { index, point in
                RouteCoordinate(latitude: point.latitude,
                                longitude: point.longitude,
                                altitude: point.altitude,
                                sequence: index)
            }
        workout.plannedRouteTitle = ATHLTHLocalization.choose(
            english: "Return to start", norwegian: "Tilbake til start"
        )
        workout.plannedComparisonRouteID = nil
        workout.returningToRouteStart = true
        workout.routeLegDistanceOffsetMeters = workout.distanceMeters
        workout.routeProgressPercent = 0
        workout.routeRemainingMeters =
            (workout.plannedRouteDistanceKilometers ?? 0) * 1000
        workout.routeDeviationMeters = nil
        workout.routeNearestPointIndex = nil
        // Keep active elapsed time, completed distance and HealthKit recording.
        active = workout
        plannedRouteLocations = []
        plannedRouteCumulativeMeters = []
        plannedRouteGeometryMeters = 0
        restoreRouteGeometry(from: workout)
        resetRouteAlertRuntime()
        persistActiveCheckpoint(force: true)
        syncLiveActivity()
    }

    func disableGhostDuringWorkout() {
        guard var workout = active,
              workout.ghostRaceTitle != nil else { return }
        workout.ghostDisabledDuringWorkout = true
        workout.ghostRaceTitle = nil
        workout.ghostOpponentName = nil
        workout.ghostDistanceDeltaMeters = nil
        workout.ghostTimeDeltaSeconds = nil
        workout.ghostAudioConfiguration = nil
        active = workout
        ghostOpponentName = nil
        resetGhostRuntime(configuration: nil)
        persistActiveCheckpoint(force: true)
        syncLiveActivity()
    }

    private func updateRouteGuidance(
        workout: inout PhoneWorkout,
        location: CLLocation
    ) {
        // GPS/HealthKit recording continues through warm-up, but the chosen
        // route and its navigation cues must not begin until the main phase.
        if workout.structuredRunningWorkout?.deferRouteUntilMain == true,
           (workout.structuredStepIndex ?? 0) == 0 ||
           workout.awaitingMainStart == true {
            return
        }
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
                            .map { $0 * 1_000 },
                    workoutDistanceMeters: max(
                        0, workout.distanceMeters -
                            (workout.routeLegDistanceOffsetMeters ?? 0)
                    ),
                    previousRouteMeters: workout.routeProgressPercent.map {
                        $0 / 100 * plannedRouteGeometryMeters
                    }
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
        workout.routeNearestPointIndex = guidance.nearestRoutePointIndex
        workout.routeCurrentCourseDegrees =
            location.course >= 0 && location.course < 360
                ? location.course : nil
        workout.routeNextBearingDegrees =
            nextBearing(
                from: location,
                nearestIndex:
                    guidance
                        .nearestRoutePointIndex
            )

        let coordinates = plannedRouteLocations.map(\.coordinate)
        let recoveryCue = ATHLTHRouteNavigationCue.recovery(
            user: location.coordinate,
            courseDegrees: location.course >= 0 && location.course < 360
                ? location.course : nil,
            route: coordinates,
            nearestIndex: guidance.nearestRoutePointIndex,
            deviationMeters: guidance.deviationMeters
        )
        evaluateRouteAlert(
            workout: workout,
            deviationMeters: guidance.deviationMeters,
            horizontalAccuracy: location.horizontalAccuracy,
            recoveryCue: recoveryCue
        )
        evaluateUpcomingTurn(
            workout: workout,
            location: location,
            route: coordinates,
            index: guidance.nearestRoutePointIndex,
            deviationMeters: guidance.deviationMeters
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

    private func evaluateUpcomingTurn(
        workout: PhoneWorkout,
        location: CLLocation,
        route: [CLLocationCoordinate2D],
        index: Int,
        deviationMeters: Double
    ) {
        guard let configuration = workout.routeAlertConfiguration,
              configuration.enabled,
              workout.audioCoachConfiguration?.enabled == true,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 25,
              deviationMeters <= configuration.deviationMeters,
              let cue = ATHLTHRouteNavigationCue.nextTurn(
                  route: route, nearestIndex: index
              ),
              let turnIndex = cue.pointIndex,
              (25...85).contains(cue.distanceMeters),
              lastSpokenRouteTurnIndex != turnIndex else { return }
        if let lastSpokenRouteTurnAt,
           Date().timeIntervalSince(lastSpokenRouteTurnAt) < 35 { return }
        lastSpokenRouteTurnIndex = turnIndex
        lastSpokenRouteTurnAt = Date()
        let meters = Int(cue.distanceMeters.rounded())
        let isRight = cue.direction == .right
        deliverRouteAlert(
            configuration: configuration,
            english: "In \(meters) meters, the route bends \(isRight ? "right" : "left").",
            norwegian: "Om \(meters) meter svinger ruten mot \(isRight ? "høyre" : "venstre").",
            haptic: .success
        )
    }

    private func evaluateRouteAlert(
        workout: PhoneWorkout,
        deviationMeters: Double,
        horizontalAccuracy: Double,
        recoveryCue: ATHLTHRouteNavigationCue.Instruction?
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
            english: "You are \(Int(deviationMeters.rounded())) meters off route. " +
                (recoveryCue?.text(norwegian: false) ?? "Head toward the marked route."),
            norwegian: "Du er \(Int(deviationMeters.rounded())) meter utenfor ruten. " +
                (recoveryCue?.text(norwegian: true) ?? "Gå mot den markerte ruten."),
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

        let channels = ATHLTHCoachAlertChannels.resolve(
            delivery: delivery,
            voiceEnabled: deliveryPreferences.audioAlertsEnabled,
            hapticsEnabled: deliveryPreferences.hapticsEnabled,
            hapticPermittedByPriority:
                guidancePriorityGate.allowsHaptic(for: priority)
        )
        if channels.haptic {
            UINotificationFeedbackGenerator()
                .notificationOccurred(haptic)
        }

        if channels.voice {
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

    private func recordRunningMinuteIfDue(
        _ workout: inout PhoneWorkout,
        force: Bool = false,
        at now: Date = Date()
    ) {
        guard workout.structuredWorkoutComplete != true,
              workout.awaitingMainStart != true,
              let plan = workout.structuredRunningWorkout,
              let index = workout.structuredStepIndex,
              plan.steps.indices.contains(index) else { return }

        let existing = (workout.recordedRunningMinutes ?? [])
            .filter { $0.stepIndex == index }
        let lastEnd = existing.last?.stepElapsedAtEndSeconds ?? 0
        let elapsedInStep = max(workout.elapsed(at: now) -
            (workout.structuredStepStartElapsedTime ?? 0), 0)
        let seconds = max(elapsedInStep - lastEnd, 0)
        guard (force && seconds >= 2) || (!force && seconds >= 60) else {
            return
        }
        let sampledDistance = existing.reduce(0.0) {
            $0 + $1.recordedDistanceMeters
        }
        let delta = max(0,
            workout.distanceMeters -
            (workout.structuredStepStartDistanceMeters ?? 0) -
            sampledDistance)
        let step = plan.steps[index]
        var timeline = workout.recordedRunningMinutes ?? []
        timeline.append(ATHLTHRecordedRunningMinute(
            stepIndex: index,
            stepElapsedAtEndSeconds: elapsedInStep,
            activeSeconds: seconds,
            recordedDistanceMeters: delta,
            watchHeartRateBPM: nil,
            targetPaceSecondsPerKilometer:
                step.targetPaceMinSecondsPerKilometer,
            targetTreadmillInclinePercent:
                step.targetTreadmillInclinePercent,
            manuallyEnteredTreadmillInclinePercent:
                workout.runEnvironment == .treadmill
                    ? workout.treadmillInclinePercent : nil
        ))
        workout.recordedRunningMinutes = timeline
    }

    private func evaluateStructuredWorkout(
        _ workout: inout PhoneWorkout,
        forceManualAdvance: Bool = false,
        at now: Date = Date()
    ) {
        guard workout.structuredWorkoutComplete != true,
              workout.awaitingMainStart != true,
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

        if !forceManualAdvance,
           (step.phase == "cooldown" ||
            (step.phase == "warmup" && plan.autoStartMainAfterWarmup != true) ||
            (step.measure == .time && plan.autoAdvanceTimedSteps == false &&
             step.phase != "warmup")) {
            return
        }
        guard forceManualAdvance || ATHLTHRunningStepEngine
            .isCompleted(
                step: step,
                elapsedTime:
                    workout.elapsed(at: now),
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

        let finishedIndex = workout.structuredStepIndex ?? 0
        // Credit scheduled time boundaries exactly, not the timer's
        // scheduling latency; the following phase receives the overshoot.
        let endElapsed: TimeInterval = {
            if !forceManualAdvance, step.measure == .time,
               let target = step.durationSeconds, target > 0 {
                return (workout.structuredStepStartElapsedTime ?? 0) + target
            }
            return workout.elapsed(at: now)
        }()
        recordRunningMinuteIfDue(&workout, force: true, at: now)
        let activeSeconds = max(0, endElapsed -
            (workout.structuredStepStartElapsedTime ?? 0))
        let segmentMeters = workout.distanceMeters -
            (workout.structuredStepStartDistanceMeters ?? 0)
        if segmentMeters >= 0 {
            var recorded = workout.recordedRunningSteps ?? []
            // Each transition is recorded at most once; an interrupted
            // or retried session must not duplicate a result.
            if !recorded.contains(where: { $0.index == finishedIndex }) {
                recorded.append(ATHLTHRecordedRunningStep(
                    index: finishedIndex,
                    title: step.title,
                    phase: step.phase,
                    activeSeconds: activeSeconds,
                    distanceMeters: segmentMeters,
                    isUserReported: workout.runEnvironment == .treadmill,
                    targetPaceSecondsPerKilometer:
                        step.targetPaceMinSecondsPerKilometer,
                    targetDurationSeconds: step.durationSeconds,
                    targetHeartRateZone: step.targetHeartRateZone,
                    targetTreadmillInclinePercent:
                        step.targetTreadmillInclinePercent
                ))
                workout.recordedRunningSteps = recorded
            }
        }

        let nextIndex = finishedIndex + 1

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
                    localizedCoachPhrase(
                        english: "Structured workout complete. Continue easy or finish when ready.",
                        norwegian: "Den planlagte økten er fullført. Fortsett rolig eller avslutt når du er klar.",
                        configuration: workout.audioCoachConfiguration ?? .disabled
                    ),
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
        // For route warm-up, the runner's manual tap IS the start-main
        // action. Keep the old two-step confirmation for library workouts.
        workout.awaitingMainStart = step.phase == "warmup" &&
            plan.autoStartMainAfterWarmup != true &&
            !(forceManualAdvance && plan.deferRouteUntilMain == true)
        if step.phase == "warmup",
           plan.deferRouteUntilMain == true {
            workout.routeLegDistanceOffsetMeters = workout.distanceMeters
        }
        workout.structuredStepStartElapsedTime = endElapsed
        workout.structuredStepStartDistanceMeters =
            workout.distanceMeters

        UINotificationFeedbackGenerator()
            .notificationOccurred(.success)

        if workout.awaitingMainStart == true {
            if workout.audioCoachConfiguration?.enabled == true {
                speak(
                    localizedCoachPhrase(
                        english: "Warm-up complete. Start the main section when ready.",
                        norwegian: "Oppvarming avsluttet. Start hoveddelen når du er klar.",
                        configuration: workout.audioCoachConfiguration ?? .disabled
                    ),
                    configuration: workout.audioCoachConfiguration,
                    priority: .structuredStep
                )
            }
            return
        }
        if workout
            .audioCoachConfiguration?
            .announceCurrentWorkoutStep == true {
            let next = plan.steps[nextIndex]
            let norwegian = localizedCoachPhrase(
                english: "en",
                norwegian: "no",
                configuration: workout.audioCoachConfiguration ?? .disabled
            ) == "no"
            speak(
                ATHLTHIntervalCoachCue.appendToStepAnnouncement(
                    ATHLTHCoachStructuredStepSpeech.phrase(
                        for: next,
                        position: .next,
                        norwegian: norwegian
                    ),
                    step: next,
                    norwegian: norwegian
                ),
                configuration:
                    workout.audioCoachConfiguration,
                priority: .structuredStep,
                event: ATHLTHCoachEvent(
                    kind: .runningStep,
                    key: "\(nextIndex)-next",
                    priority: .structuredStep,
                    validFor: 15
                )
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

        let position: ATHLTHCoachStructuredStepSpeech.Position
        switch prefix {
        case "Starting": position = .starting
        case "Next": position = .next
        default: position = .current
        }
        let norwegian = localizedCoachPhrase(
            english: "en",
            norwegian: "no",
            configuration: workout.audioCoachConfiguration ?? .disabled
        ) == "no"
        speak(
            ATHLTHIntervalCoachCue.appendToStepAnnouncement(
                ATHLTHCoachStructuredStepSpeech.phrase(
                    for: plan.steps[workout.structuredStepIndex ?? 0],
                    position: position,
                    norwegian: norwegian
                ),
                step: plan.steps[workout.structuredStepIndex ?? 0],
                norwegian: norwegian
            ),
            configuration:
                workout.audioCoachConfiguration,
            priority: .structuredStep,
            event: ATHLTHCoachEvent(
                kind: .runningStep,
                key: "\(workout.structuredStepIndex ?? 0)-\(prefix)",
                priority: .structuredStep,
                validFor: 15
            )
        )
    }

    private func announceFuelIfDue(
        _ workout: PhoneWorkout,
        configuration: WatchAudioCoachConfiguration
    ) {
        guard !coachSpeechPaused,
              workout.resumedAt != nil,
              let next = nextFuelAnnouncementSeconds
        else { return }

        let elapsed = workout.elapsed(at: Date())
        guard elapsed >= next else { return }
        nextFuelAnnouncementSeconds = ATHLTHFuelVoicePrompt.nextDue(
            after: elapsed,
            config: configuration
        )

        // No stale voice prompts after pause, backgrounding or reconnect.
        guard ATHLTHFuelVoicePrompt.isFreshDue(
            elapsed: elapsed,
            scheduled: next
        ),
        let phrase = ATHLTHFuelVoicePrompt.phrase(
            config: configuration
        ) else { return }

        speak(
            phrase,
            configuration: configuration,
            priority: .routineCoach,
            event: ATHLTHCoachEvent(
                kind: .routineMilestone,
                key: "fuel:\(Int(next))",
                priority: .routineCoach,
                validFor: 12
            )
        )
    }

    /// Workout-relative voice cues for the current scheduled interval. The
    /// one-second structured tick drives this; there is no independent clock.
    private func announceStructuredIntervalCues(
        _ workout: PhoneWorkout,
        elapsed: TimeInterval
    ) {
        guard let audio = workout.audioCoachConfiguration,
              audio.enabled,
              workout.awaitingMainStart != true,
              workout.structuredWorkoutComplete != true,
              let plan = workout.structuredRunningWorkout,
              let index = workout.structuredStepIndex,
              plan.steps.indices.contains(index) else { return }

        let step = plan.steps[index]
        guard step.measure == .time,
              let length = step.durationSeconds,
              length > 0 else { return }
        let passed = max(0, elapsed -
            (workout.structuredStepStartElapsedTime ?? 0))
        let remaining = max(0, length - passed)
        let norwegian = localizedCoachPhrase(
            english: "en", norwegian: "no", configuration: audio
        ) == "no"

        if let warning = plan.intervalCoachCountdownSeconds,
           warning >= 5, warning < length,
           remaining > 0, remaining <= warning,
           remaining > warning - 1.5 {
            speak(
                norwegian
                    ? "\(Int(ceil(remaining))) sekunder igjen av \(step.title)"
                    : "\(Int(ceil(remaining))) seconds left in \(step.title)",
                configuration: audio,
                priority: .structuredStep,
                event: ATHLTHCoachEvent(
                    kind: .runningStep,
                    key: "phone-interval-warning:\(workout.id):\(index)",
                    priority: .structuredStep,
                    validFor: 8
                )
            )
            return
        }

        guard let cadence = plan.intervalCoachCueEverySeconds,
              cadence.isFinite, cadence >= 15,
              passed >= cadence, remaining > 2 else { return }
        let slot = Int(floor(passed / cadence))
        guard slot > 0,
              passed - Double(slot) * cadence < 1.5 else { return }
        speak(
            norwegian
                ? "\(Int(ceil(remaining))) sekunder igjen av \(step.title)"
                : "\(Int(ceil(remaining))) seconds left in \(step.title)",
            configuration: audio,
            priority: .routineCoach,
            event: ATHLTHCoachEvent(
                kind: .routineMilestone,
                key: "phone-interval-progress:\(workout.id):\(index):\(slot)",
                priority: .routineCoach,
                validFor: 8
            )
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

        announceFuelIfDue(workout, configuration: configuration)
        evaluateCustomAudioCoachRules(workout, configuration: configuration)

        var shouldAnnounce = false
        var milestoneKeys: [String] = []

        if let interval =
                configuration.distanceIntervalMeters,
           interval > 0,
           let next =
                nextDistanceAnnouncementMeters,
           workout.distanceMeters >= next {
            milestoneKeys.append("d\(Int(next.rounded()))")
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
            milestoneKeys.append("t\(Int(next.rounded()))")
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

        let activeStep: WatchRunningWorkoutStep? = {
            guard workout.structuredWorkoutComplete != true,
                  let plan = workout.structuredRunningWorkout,
                  plan.steps.indices.contains(workout.structuredStepIndex ?? 0)
            else { return nil }
            return plan.steps[workout.structuredStepIndex ?? 0]
        }()
        guard ATHLTHCoachRoutineContextPolicy.shouldSpeakMilestone(
            step: activeStep,
            elapsedInStep: workout.elapsed(at: Date()) -
                (workout.structuredStepStartElapsedTime ?? 0),
            distanceInStepMeters: workout.distanceMeters -
                (workout.structuredStepStartDistanceMeters ?? 0)
        ) else { return }

        var parts: [String] = []
        let norwegian =
            localizedCoachPhrase(
                english: "en",
                norwegian: "no",
                configuration: configuration
            ) == "no"

        if configuration.announceDistance {
            parts.append(
                String(
                    format:
                        norwegian ? "%.1f kilometer" : "%.1f kilometers",
                    workout.distanceMeters /
                        1_000
                )
            )
        }

        if configuration.announceElapsedTime {
            parts.append(
                durationPhrase(elapsed, norwegian: norwegian)
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
                (norwegian ? "Gjennomsnittstempo " : "Average pace ") +
                    pacePhrase(pace, norwegian: norwegian)
            )
        }

        if configuration
            .announceRemainingRouteDistance,
           let remaining =
                workout.routeRemainingMeters {
            parts.append(
                remaining < 1_000
                    ? (norwegian
                        ? "\(Int(remaining.rounded())) meter igjen"
                        : "\(Int(remaining.rounded())) meters remaining")
                    : String(
                        format:
                            norwegian
                                ? "%.1f kilometer igjen"
                                : "%.1f kilometers remaining",
                        remaining / 1_000
                    )
            )
        }

        if configuration
            .announceEstimatedRemainingRouteTime,
           let remaining =
                workout.routeRemainingMeters,
           ATHLTHCoachSensorFreshness.validPace(
               workout.currentPaceSecondsPerKilometer,
               sampledAt: coachPaceSampleAt
           ),
           let pace =
                workout
                    .currentPaceSecondsPerKilometer {
            parts.append(
                (norwegian
                    ? "Omtrent \(durationPhrase((remaining / 1_000) * pace, norwegian: true)) igjen"
                    : "About \(durationPhrase((remaining / 1_000) * pace)) remaining")
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

        if let activeStep,
           let remaining = ATHLTHCoachStructuredStepSpeech.remainingSummary(
                for: activeStep,
                elapsedInStep: elapsed -
                    (workout.structuredStepStartElapsedTime ?? 0),
                distanceInStepMeters: workout.distanceMeters -
                    (workout.structuredStepStartDistanceMeters ?? 0),
                announceTime: configuration.announceRemainingStepTime,
                announceDistance: configuration.announceRemainingStepDistance,
                norwegian: norwegian
           ) {
            parts.append(remaining)
        }

        guard !parts.isEmpty else {
            return
        }

        if let feedback = ATHLTHCoachGoalEncouragement.phrase(
            style: configuration.speechStyle ?? .balanced,
            step: activeStep,
            paceSecondsPerKilometer: workout.currentPaceSecondsPerKilometer,
            paceSampleAt: coachPaceSampleAt,
            elapsedInStep: elapsed -
                (workout.structuredStepStartElapsedTime ?? 0),
            lastSpokenAt: lastGoalEncouragementAt,
            norwegian: norwegian
        ) {
            parts.append(feedback)
            lastGoalEncouragementAt = Date()
        }

        speak(
            parts.joined(
                separator: ". "
            ),
            configuration: configuration,
            priority: .routineCoach,
            event: ATHLTHCoachEvent(
                kind: .routineMilestone,
                key: milestoneKeys.joined(separator: "-"),
                priority: .routineCoach,
                validFor: 10
            )
        )
    }

    private func evaluateCustomAudioCoachRules(
        _ workout: PhoneWorkout,
        configuration: WatchAudioCoachConfiguration
    ) {
        let elapsed = workout.elapsed(at: Date())
        let freshPace = ATHLTHCoachSensorFreshness.validPace(
            workout.currentPaceSecondsPerKilometer,
            sampledAt: coachPaceSampleAt
        ) ? workout.currentPaceSecondsPerKilometer : nil
        let norwegian = localizedCoachPhrase(
            english: "en",
            norwegian: "no",
            configuration: configuration
        ) == "no"
        let messages = ATHLTHAudioCoachRuleDelivery.dueMessages(
            rules: configuration.customRules ?? [],
            distanceMeters: workout.distanceMeters,
            elapsedSeconds: elapsed,
            paceSecondsPerKilometer: freshPace,
            heartRateBPM: nil,
            norwegian: norwegian,
            lastSlots: &customAudioCoachLastSlots
        )
        guard !messages.isEmpty else { return }
        speak(
            messages.joined(separator: ". "),
            configuration: configuration,
            priority: .routineCoach,
            event: ATHLTHCoachEvent(
                kind: .routineMilestone,
                key: "custom:\(Int(elapsed)):\(Int(workout.distanceMeters))",
                priority: .routineCoach,
                validFor: 10
            )
        )
    }

    private func speak(
        _ phrase: String,
        configuration:
            WatchAudioCoachConfiguration?,
        priority:
            ATHLTHGuidancePriority =
                .routineCoach,
        event: ATHLTHCoachEvent? = nil,
        rememberForReplay: Bool = true
    ) {
        guard !phrase.isEmpty,
              ATHLTHCoachVoicePausePolicy.allowsSpeech(
                  coachEnabled:
                      active?.audioCoachConfiguration?.enabled == true,
                  speechPaused: coachSpeechPaused,
                  priority: priority
              )
        else {
            return
        }
        if let event,
           !coachEventLedger.canDeliver(event) {
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
                        speechSynthesizer.isSpeaking ||
                        azureCoachSpeech.isBusy,
                    quietPeriodSeconds:
                        configuration
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
                        text: phrase
                    )
                )
            }
            return
        case .interruptAndDeliver:
            azureCoachSpeech.stop()
            speechSynthesizer
                .stopSpeaking(
                    at: .immediate
                )
        case .deliver:
            break
        }

        if let event {
            coachEventLedger.didDeliver(event)
        }

        let spokenPhrase = rememberForReplay
            ? (configuration.speechStyle ?? .balanced).render(
                phrase,
                language: configuration.language,
                priority: priority,
                eventKind: event?.kind
            )
            : phrase
        let utterance =
            AVSpeechUtterance(
                string: spokenPhrase
            )

        utterance.voice = ATHLTHCoachPreferredSystemVoice.resolve(
            selectedIdentifier: configuration.voiceIdentifier,
            language: configuration.language
        )

        utterance.rate =
            configuration
                .resolvedSpeechRate
        utterance.volume =
            configuration
                .resolvedSpeechVolume

        let routedToAzure = azureCoachSpeech.begin(
            spokenPhrase,
            voiceIdentifier: configuration.voiceIdentifier,
            duckMusic: configuration.shouldDuckOtherAudio,
            onFallback: { [weak self] in
                guard let self,
                      self.active?.audioCoachConfiguration?.enabled == true,
                      !self.coachSpeechPaused
                else { return }
                try? ATHLTHSpokenAudioSession.activate(
                    duckOtherAudio: configuration.shouldDuckOtherAudio,
                    owner: self.audioOwner
                )
                self.speechSynthesizer.speak(utterance)
                self.watchLocalCoachSpeech(utterance)
            },
            onFinished: { [weak self] in
                guard let self else { return }
                self.guidancePriorityGate.voiceDidFinish()
                self.deliverNextQueuedCoachCue()
            }
        )
        if !routedToAzure {
            try? ATHLTHSpokenAudioSession.activate(
                duckOtherAudio: configuration.shouldDuckOtherAudio,
                owner: audioOwner
            )
            speechSynthesizer.speak(utterance)
            watchLocalCoachSpeech(utterance)
        }
        if rememberForReplay,
           ATHLTHCoachReplayMemory.mayRemember(priority: priority) {
            coachReplayMemory.remember(spokenPhrase, priority: priority)
            lastCoachMessage = coachReplayMemory.text
        }
    }

    private func deliverNextQueuedCoachCue() {
        guard !speechSynthesizer.isSpeaking,
              !azureCoachSpeech.isBusy,
              let next = coachCueQueue.popNext()
        else { return }
        speak(
            next.text,
            configuration: active?.audioCoachConfiguration,
            priority: next.event.priority,
            event: next.event
        )
    }

    /// Some AirPods/Spotify handoffs lose AVSpeechSynthesizer's completion.
    /// Poll the synthesizer and release ducking promptly when it falls idle.
    private func watchLocalCoachSpeech(_ utterance: AVSpeechUtterance) {
        localSpeechWatchdog?.cancel()
        let maximumSeconds = max(
            10, min(45, Double(utterance.speechString.count) / 8 + 10)
        )
        localSpeechWatchdog = Task { @MainActor [weak self] in
            for _ in 0..<Int(ceil(maximumSeconds)) {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard let self, !Task.isCancelled else { return }
                if !self.speechSynthesizer.isSpeaking &&
                    !self.azureCoachSpeech.isBusy {
                    self.localSpeechWatchdog = nil
                    ATHLTHSpokenAudioSession.deactivate(owner: self.audioOwner)
                    self.guidancePriorityGate.voiceDidFinish()
                    self.deliverNextQueuedCoachCue()
                    return
                }
            }
            guard let self, !Task.isCancelled,
                  !self.azureCoachSpeech.isBusy else { return }
            self.speechSynthesizer.stopSpeaking(at: .immediate)
            self.localSpeechWatchdog = nil
            ATHLTHSpokenAudioSession.deactivate(owner: self.audioOwner)
            self.guidancePriorityGate.voiceDidFinish()
            self.deliverNextQueuedCoachCue()
        }
    }

    private func deactivateCoachAudioSession() {
        localSpeechWatchdog?.cancel()
        localSpeechWatchdog = nil
        azureCoachSpeech.stop()
        speechSynthesizer.stopSpeaking(
            at: .immediate
        )

        ATHLTHSpokenAudioSession
            .deactivate(owner: audioOwner)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.speechSynthesizer.isSpeaking,
                  !self.azureCoachSpeech.isBusy
            else {
                // A delayed AVSpeechSynthesizer completion must not release
                // the audio session while a newer Azure cue is playing.
                return
            }

            self.guidancePriorityGate.voiceDidFinish()
            self.localSpeechWatchdog?.cancel()
            self.localSpeechWatchdog = nil

            ATHLTHSpokenAudioSession
                .deactivate(owner: audioOwner)
            self.deliverNextQueuedCoachCue()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.speechSynthesizer.isSpeaking,
                  !self.azureCoachSpeech.isBusy
            else {
                // A delayed AVSpeechSynthesizer completion must not release
                // the audio session while a newer Azure cue is playing.
                return
            }

            self.guidancePriorityGate.voiceDidFinish()
            self.localSpeechWatchdog?.cancel()
            self.localSpeechWatchdog = nil

            ATHLTHSpokenAudioSession
                .deactivate(owner: audioOwner)
            self.deliverNextQueuedCoachCue()
        }
    }

    private func durationPhrase(
        _ seconds: TimeInterval,
        norwegian: Bool = false
    ) -> String {
        let totalMinutes =
            max(Int((seconds / 60).rounded()), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            if norwegian {
                return minutes > 0
                    ? "\(hours) timer \(minutes) minutter"
                    : "\(hours) timer"
            }
            return minutes > 0
                ? "\(hours) hours \(minutes) minutes"
                : "\(hours) hours"
        }

        return norwegian
            ? "\(minutes) minutter"
            : "\(minutes) minutes"
    }

    private func pacePhrase(
        _ seconds: TimeInterval,
        norwegian: Bool = false
    ) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(
            format: norwegian
                ? "%d minutter %02d sekunder per kilometer"
                : "%d minutes %02d seconds per kilometer",
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
        let runningStepReadout = currentStep.map {
            ATHLTHRunIntervalReadout.resolve(
                step: $0,
                elapsedSeconds: max(
                    workout.elapsed(at: Date()) -
                        (workout.structuredStepStartElapsedTime ?? 0), 0
                ),
                distanceMeters: max(
                    workout.distanceMeters -
                        (workout.structuredStepStartDistanceMeters ?? 0), 0
                )
            )
        }
        let runningStepProgress =
            currentStep.map {
                if workout.awaitingMainStart == true { return 0.0 }
                return ATHLTHRunningStepEngine
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
                runningOverallProgress:
                    runningStepProgress.flatMap { progress in
                        workout.structuredRunningWorkout.map {
                            ATHLTHRunningStepEngine.overallProgress(
                                steps: $0.steps,
                                index: workout.structuredStepIndex ?? 0,
                                currentStepProgress: progress
                            )
                        }
                    },
                runningStepTargetTreadmillInclinePercent:
                    currentStep?.targetTreadmillInclinePercent,
                runningStepTargetPaceSecondsPerKilometer:
                    currentStep?.targetPaceMinSecondsPerKilometer,
                runningManualAdvanceRequired:
                    currentStep.map { step in
                        workout.awaitingMainStart == true ||
                        (step.phase == "warmup" &&
                         workout.structuredRunningWorkout?.autoStartMainAfterWarmup != true) ||
                        step.phase == "cooldown" ||
                        step.measure == .open ||
                        workout.structuredRunningWorkout?.autoAdvanceTimedSteps == false
                    },
                runningAwaitingMainStart: workout.awaitingMainStart == true,
                runningNextStepTitle:
                    nextStepTitle,
                runningStepRemainingSeconds:
                    runningStepReadout?.unit == .seconds
                        ? runningStepReadout?.remaining : nil,
                runningStepRemainingMeters:
                    runningStepReadout?.unit == .meters
                        ? runningStepReadout?.remaining : nil,
                runningStepCoachBrief: currentStep?.coachBrief,
                runningStepPhase: currentStep?.phase,
                runningStepTargetHeartRateZone: currentStep?.targetHeartRateZone,
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

    func removeWorkoutFromHistory(
        matching workoutIDs: Set<UUID>
    ) {
        guard !workoutIDs.isEmpty else {
            return
        }

        if let accountID, let journal = PhoneWorkoutCompletionJournal.read(userID: accountID),
           workoutIDs.contains(journal.id) || journal.healthID.map(workoutIDs.contains) == true {
            PhoneWorkoutCompletionJournal.remove(userID: accountID)
        }
        history.removeAll { workout in
            workoutIDs.contains(workout.id) ||
            workout.healthID
                .map(workoutIDs.contains) == true
        }

        persistHistory()
    }

    private func persistTreadmillInclineOverrides() {
        guard let accountID else {
            return
        }

        AccountLocalStorage.write(
            treadmillInclineOverrides,
            name: "treadmillInclineOverrides",
            userID: accountID
        )
        ATHLTHTrainingDataChangeSignal.post(
            userID: accountID
        )
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
            if self.active?.runEnvironment == .outdoor,
               (self.manager.authorizationStatus == .denied ||
                self.manager.authorizationStatus == .restricted) {
                self.pause()
            }
            self.beginIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.accept(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.active?.runEnvironment == .outdoor else { return }
            self.message = "GPS is unavailable. Time continues; distance will resume when the signal returns."
            self.lastLocation = nil
            self.coachPaceSampleAt = nil
        }
    }

    private func resetIndoorProbe() {
        indoorSuggestionAvailable = false
        indoorFirstReliableFix = nil
        indoorLastReliableFix = nil
        indoorAcceptedFixCount = 0
    }

    /// The recorded GPS path is cumulative: a runner circling a small track
    /// must not be mistaken for someone standing still.
    private func evaluateIndoorSuggestion(now: Date = Date()) {
        guard var workout = active else { return }
        guard ATHLTHIndoorRunDetection.shouldOffer(
            elapsedWallSeconds: now.timeIntervalSince(workout.start),
            acceptedDistanceMeters: workout.distanceMeters,
            firstReliableFix: indoorFirstReliableFix,
            lastReliableFix: indoorLastReliableFix,
            acceptedFixCount: indoorAcceptedFixCount,
            now: now,
            isOutdoor: workout.runEnvironment == .outdoor,
            manualPause: workout.resumedAt == nil && !automaticPauseActive,
            hasPlannedRouteOrGhost: workout.plannedRouteID != nil ||
                workout.ghostRaceTitle != nil,
            alreadyPrompted: workout.indoorPromptedThisSession == true
        ) else { return }
        workout.indoorPromptedThisSession = true
        workout.indoorPromptPending = true
        active = workout
        indoorSuggestionAvailable = true
        persistActiveCheckpoint(force: true)
    }

    func dismissIndoorSuggestion() {
        indoorSuggestionAvailable = false
        guard var workout = active else { return }
        workout.indoorPromptedThisSession = true
        workout.indoorPromptPending = false
        active = workout
        persistActiveCheckpoint(force: true)
    }

    /// Only the athlete may switch the capture mode. Retain the ongoing
    /// workout identity, active time, structured steps and existing evidence.
    /// Never treat noisy GPS distance as indoor movement. A treadmill belt
    /// speed must be entered explicitly to estimate future distance.
    @discardableResult
    func switchRunningEnvironmentToIndoor(_ venue: ATHLTHIndoorRunVenue) -> Bool {
        guard var workout = active, !saving else { return false }
        let now = Date()
        if workout.runEnvironment == .treadmill {
            guard workout.indoorVenue != venue else { return true }
            workout.advanceTreadmillDistance(at: now)
            workout.indoorVenue = venue
            workout.treadmillSpeedKilometersPerHour = nil
            workout.treadmillDistanceElapsedSeconds = workout.elapsed(at: now)
            workout.treadmillInclinePercent = venue == .treadmill ? 0 : nil
            active = workout
            persistActiveCheckpoint(force: true)
            syncLiveActivity()
            return true
        }
        guard workout.runEnvironment == .outdoor else { return false }
        let originalDistance = max(0, workout.distanceMeters)
        workout.gpsDistanceBeforeIndoorSwitchMeters = originalDistance
        workout.indoorSwitchActiveSeconds = workout.elapsed(at: now)
        workout.indoorVenue = venue
        workout.indoorPromptedThisSession = true
        workout.indoorPromptPending = false
        workout.runEnvironment = .treadmill
        workout.autoPauseEnabled = false
        workout.treadmillInclinePercent = venue == .treadmill ? 0 : nil
        workout.treadmillSpeedKilometersPerHour = nil
        workout.treadmillDistanceElapsedSeconds = workout.elapsed(at: now)
        workout.distanceMeters = 0
        workout.structuredStepStartDistanceMeters = 0
        workout.currentPaceSecondsPerKilometer = nil
        workout.finalLeaderboardEligible = false
        workout.plannedRouteID = nil
        workout.plannedComparisonRouteID = nil
        workout.plannedRouteTitle = nil
        workout.plannedRouteDistanceKilometers = nil
        workout.plannedRouteCoordinates = nil
        workout.plannedRouteSource = nil
        workout.ghostDisabledDuringWorkout = true
        workout.ghostAudioConfiguration = nil
        // A user choosing indoors during auto-pause should not remain
        // incorrectly paused because the GPS device is stationary.
        if automaticPauseActive {
            if var pauses = workout.pauses,
               let last = pauses.indices.last,
               pauses[last].endedAt == nil {
                pauses[last].endedAt = now
                workout.pauses = pauses
            }
            workout.resumedAt = now
            workout.lastCheckpoint = now
        }
        active = workout
        automaticPauseActive = false
        autoPauseDetector.reset(enabled: false)
        resetIndoorProbe()
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.distanceFilter = 5
        lastLocation = nil
        coachPaceSampleAt = nil
        resetRouteRuntime()
        resetGhostRuntime(configuration: nil)
        startTreadmillTicksIfNeeded()
        persistActiveCheckpoint(force: true)
        syncLiveActivity()
        message = ATHLTHLocalization.choose(
            english: "Indoor mode active. GPS tracking stopped; workout time and intervals continue.",
            norwegian: "Innendørsmodus er aktiv. GPS-sporing stoppet; økttid og intervaller fortsetter."
        )
        return true
    }

    private func accept(
        _ locations: [CLLocation]
    ) {
        // Delayed CLLocation callbacks must not invent treadmill distance.
        guard var workout = active,
              workout.runEnvironment == .outdoor
        else { return }

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

            // Reliable GPS fixes must be counted even while GPS auto-pause
            // is active; otherwise a stationary treadmill session would
            // never meet the 15-minute eligibility window.
            if indoorFirstReliableFix == nil {
                indoorFirstReliableFix = location.timestamp
            }
            indoorLastReliableFix = location.timestamp
            indoorAcceptedFixCount += 1

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
