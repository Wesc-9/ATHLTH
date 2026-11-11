import CoreLocation
import MapKit
import SwiftUI

@MainActor
private final class QuickStartRouteLocationProbe:
    NSObject,
    ObservableObject,
    CLLocationManagerDelegate
{
    @Published private(set)
    var location: CLLocation?

    private let manager =
        CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy =
            kCLLocationAccuracyHundredMeters
    }

    func refresh() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager
                .requestWhenInUseAuthorization()

        case .authorizedAlways,
             .authorizedWhenInUse:
            manager.requestLocation()

        default:
            break
        }
    }

    nonisolated func
        locationManagerDidChangeAuthorization(
            _ manager: CLLocationManager
        ) {
        guard manager.authorizationStatus ==
                .authorizedAlways ||
                manager.authorizationStatus ==
                .authorizedWhenInUse
        else {
            return
        }

        manager.requestLocation()
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations
            locations: [CLLocation]
    ) {
        let validLocations =
            locations.filter {
                $0.horizontalAccuracy >= 0
            }

        guard let location =
                validLocations.min(
                    by: {
                        $0.horizontalAccuracy <
                            $1.horizontalAccuracy
                    }
                )
        else {
            return
        }

        Task { @MainActor [weak self] in
            self?.location = location
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {}
}

struct AudioCoachDraft {
    // New workouts start with the simple coach enabled unless the athlete's
    // saved default explicitly opts out.
    var enabled = true
    var distanceTriggerEnabled = true
    var timeTriggerEnabled = false
    var distanceIntervalKilometers = 1.0
    var timeIntervalMinutes = 10
    /// Preserve precise 15-second to 120-minute Watch cadence.
    var timeIntervalSeconds = 600
    // Existing rules and motivation engine are shared with Settings and Watch.
    // Per-workout selections are snapshots, never edits to the saved preset.
    var customRules: [ATHLTHAudioCoachRule] = []
    var smartPrompts = ATHLTHAudioCoachSmartSettings()

    var announceDistance = true
    var announceElapsedTime = true
    var announceAveragePace = true
    var announceClockTime = false
    var announceHeartRate = false

    var announceRemainingRouteDistance = true
    var announceEstimatedRemainingRouteTime = true

    var announceCurrentWorkoutStep = true
    var announceRemainingStepTime = true
    var announceRemainingStepDistance = true
    var duckOtherAudio = true
    var voiceIdentifier: String? = nil
    var speechRate: Double = 0.48
    var speechVolume: Double = 1.0
    var speechStyle: ATHLTHCoachSpeechStyle = .balanced
    var announceWorkoutStart = true
    var announcePauseResume = true
    var announceWorkoutComplete = true
    var guidanceQuietPeriodSeconds:
        TimeInterval = 10

    var language: WatchAudioCoachLanguage = .system

    init() {
        smartPrompts.motivationEnabled = true
        smartPrompts.motivationIntervalSeconds = 180
    }

    /// Explicitly resets content, but retains language, chosen voice and
    /// music volume/ducking; never silently discards a saved global profile.
    mutating func applySimpleAudioCoach() {
        enabled = true
        distanceTriggerEnabled = true
        timeTriggerEnabled = false
        distanceIntervalKilometers = 1.0
        timeIntervalMinutes = 10
        timeIntervalSeconds = 600
        customRules = []
        announceDistance = true
        announceElapsedTime = true
        announceAveragePace = true
        announceClockTime = false
        announceHeartRate = false
        announceRemainingRouteDistance = false
        announceEstimatedRemainingRouteTime = false
        announceCurrentWorkoutStep = false
        announceRemainingStepTime = false
        announceRemainingStepDistance = false
        announceWorkoutStart = true
        announcePauseResume = true
        announceWorkoutComplete = true
        smartPrompts.motivationEnabled = true
        smartPrompts.motivationIntervalSeconds = 180
        smartPrompts.randomEncouragementEnabled = false
        smartPrompts.contextualFeedbackEnabled = false
        smartPrompts.announceCurrentHeartRateZone = false
        smartPrompts.customEncouragements = []
        smartPrompts.landmarks = []
        // Switching from a complex profile back to Standard must truly
        // remove every advanced trigger; do not keep invisible Watch rules.
        smartPrompts.maximumHeartRateBPM = nil
        smartPrompts.preferredHeartRateZone = nil
        smartPrompts.measuredZoneAnnouncementIntervalSeconds = nil
        smartPrompts.targetZoneVoiceAlertsEnabled = nil
        smartPrompts.confirmWhenBackInZone = nil
        smartPrompts.coachingMode = .automatic
        smartPrompts.strongStartDurationSeconds = nil
        smartPrompts.pushWhenBelowTargetZone = nil
        smartPrompts.pushWhenBelowTargetPace = nil
        smartPrompts.pushOnUnexpectedPaceDrop = nil
        smartPrompts.paceDropThresholdPercent = nil
        smartPrompts.adaptiveCooldownSeconds = nil
    }

    /// One-tap announcement template. A complete distance/time/pulse cue
    /// is one rule and can be edited as a group later.
    @discardableResult
    mutating func addKilometerMetricsBundle() -> Bool {
        guard customRules.count < 20 else { return false }
        enabled = true
        let alreadyExists = customRules.contains {
            $0.trigger == .distance && $0.validatedInterval == 1_000 &&
            $0.selectedMetrics == [.distance, .elapsedTime, .heartRate]
        }
        // The combined 1 km rule replaces the standard 1 km cue.
        // Otherwise both are scheduled and the athlete hears duplicates.
        distanceTriggerEnabled = false
        guard !alreadyExists else { return false }
        customRules.append(ATHLTHAudioCoachRule(
            trigger: .distance,
            metric: .distance,
            interval: 1_000,
            additionalMetrics: [.elapsedTime, .heartRate]
        ))
        return true
    }

    /// Preserve voice, language, music routing and per-workout session data.
    var experiencePreset: ATHLTHCoachExperiencePreset? {
        guard enabled else { return nil }
        return ATHLTHCoachExperiencePreset.allCases.first { preset in
            ATHLTHCoachContentLevel.matching(configuration()) == preset.contentLevel
                && distanceTriggerEnabled
                && !timeTriggerEnabled
                && abs(distanceIntervalKilometers - preset.distanceIntervalKilometers) < 0.001
        }
    }

    mutating func applyExperience(_ preset: ATHLTHCoachExperiencePreset) {
        enabled = true
        let values = preset.contentLevel.applying(to: configuration())
        announceDistance = values.announceDistance
        announceElapsedTime = values.announceElapsedTime
        announceAveragePace = values.announceAveragePace
        announceClockTime = values.announceClockTime
        announceHeartRate = values.announceHeartRate
        announceRemainingRouteDistance = values.announceRemainingRouteDistance
        announceEstimatedRemainingRouteTime = values.announceEstimatedRemainingRouteTime
        announceCurrentWorkoutStep = values.announceCurrentWorkoutStep
        announceRemainingStepTime = values.announceRemainingStepTime
        announceRemainingStepDistance = values.announceRemainingStepDistance
        announceWorkoutStart = values.shouldAnnounceWorkoutStart
        announcePauseResume = values.shouldAnnouncePauseResume
        announceWorkoutComplete = values.shouldAnnounceWorkoutComplete
        distanceTriggerEnabled = true
        timeTriggerEnabled = false
        distanceIntervalKilometers = preset.distanceIntervalKilometers
    }

    @MainActor
    mutating func load(from settings: AppSettingsStore) {
        // The user can turn off the coach in global Settings. Fresh Quick
        // sessions inherit that explicit choice, defaulting to on otherwise.
        enabled = settings.audioCoachEnabledByDefault
        distanceTriggerEnabled =
            settings.audioCoachDistanceTriggerEnabled
        timeTriggerEnabled =
            settings.audioCoachTimeTriggerEnabled
        distanceIntervalKilometers =
            settings.audioCoachDistanceIntervalKilometers
        timeIntervalMinutes =
            settings.audioCoachTimeIntervalMinutes
        timeIntervalSeconds = min(max(settings.audioCoachTimeIntervalSeconds, 15), 7_200)
        customRules = settings.audioCoachCustomRules
        smartPrompts = settings.audioCoachSmartSettings
        announceDistance =
            settings.audioCoachAnnounceDistance
        announceElapsedTime =
            settings.audioCoachAnnounceElapsedTime
        announceAveragePace =
            settings.audioCoachAnnounceAveragePace
        announceClockTime =
            settings.audioCoachAnnounceClockTime
        announceHeartRate =
            settings.audioCoachAnnounceHeartRate
        announceRemainingRouteDistance =
            settings.audioCoachAnnounceRemainingRouteDistance
        announceEstimatedRemainingRouteTime =
            settings.audioCoachAnnounceEstimatedRemainingRouteTime
        announceCurrentWorkoutStep =
            settings.audioCoachAnnounceCurrentWorkoutStep
        announceRemainingStepTime =
            settings.audioCoachAnnounceRemainingStepTime
        announceRemainingStepDistance =
            settings.audioCoachAnnounceRemainingStepDistance
        duckOtherAudio =
            settings.audioCoachDuckOtherAudio
        voiceIdentifier =
            settings.audioCoachVoiceIdentifier
        speechRate =
            settings.audioCoachSpeechRate
        speechVolume =
            settings.audioCoachSpeechVolume
        speechStyle =
            settings.audioCoachSpeechStyle
        announceWorkoutStart =
            settings.audioCoachAnnounceWorkoutStart
        announcePauseResume =
            settings.audioCoachAnnouncePauseResume
        announceWorkoutComplete =
            settings.audioCoachAnnounceWorkoutComplete
        guidanceQuietPeriodSeconds =
            TimeInterval(
                settings
                    .guidanceQuietPeriodSeconds
            )
        language = settings.audioCoachLanguage
    }

    /// Load a reusable named coach profile just for this workout.
    /// Voice configuration, event wording and delivery stay in the same
    /// existing shared Audio Coach engines.
    mutating func load(profile: ATHLTHAudioCoachProfile) {
        let config = profile.configuration
        enabled = true
        language = config.language
        customRules = config.customRules ?? []
        smartPrompts = config.smartPrompts ?? ATHLTHAudioCoachSmartSettings()
        distanceTriggerEnabled = config.distanceIntervalMeters != nil
        distanceIntervalKilometers = (config.distanceIntervalMeters ?? 1_000) / 1_000
        timeTriggerEnabled = config.timeIntervalSeconds != nil
        timeIntervalMinutes = max(1, Int(((config.timeIntervalSeconds ?? 600) / 60).rounded()))
        timeIntervalSeconds = Int(min(max(config.timeIntervalSeconds ?? 600, 15), 7_200))
        announceDistance = config.announceDistance
        announceElapsedTime = config.announceElapsedTime
        announceAveragePace = config.announceAveragePace
        announceClockTime = config.announceClockTime
        announceHeartRate = config.announceHeartRate
        announceRemainingRouteDistance = config.announceRemainingRouteDistance
        announceEstimatedRemainingRouteTime = config.announceEstimatedRemainingRouteTime
        announceCurrentWorkoutStep = config.announceCurrentWorkoutStep
        announceRemainingStepTime = config.announceRemainingStepTime
        announceRemainingStepDistance = config.announceRemainingStepDistance
        duckOtherAudio = config.duckOtherAudio ?? true
        guidanceQuietPeriodSeconds = config.guidanceQuietPeriodSeconds ?? 10
        voiceIdentifier = config.voiceIdentifier
        speechRate = Double(config.speechRate ?? 0.48)
        speechVolume = Double(config.speechVolume ?? 1.0)
        speechStyle = config.speechStyle ?? .balanced
        announceWorkoutStart = config.announceWorkoutStart ?? true
        announcePauseResume = config.announcePauseResume ?? true
        announceWorkoutComplete = config.announceWorkoutComplete ?? true
    }

    /// Shared by planned-workout editing, including old saved sessions.
    /// Preserve every existing setting when loading a session override.
    mutating func load(configuration config: WatchAudioCoachConfiguration) {
        load(profile: ATHLTHAudioCoachProfile(
            name: "Workout", configuration: config
        ))
        enabled = config.enabled
    }

    /// Apply just the options surfaced by the premium studio. Do not lose
    /// fuel, strength, voice lease or other settings held by older workouts.
    func applying(
        to original: WatchAudioCoachConfiguration,
        maximumHeartRateBPM: Double? = nil
    ) -> WatchAudioCoachConfiguration {
        let values = configuration(
            routeDistanceMeters: original.routeDistanceMeters,
            maximumHeartRateBPM: maximumHeartRateBPM
        )
        var saved = original
        saved.enabled = values.enabled
        saved.language = values.language
        saved.distanceIntervalMeters = values.distanceIntervalMeters
        saved.timeIntervalSeconds = values.timeIntervalSeconds
        saved.customRules = values.customRules
        saved.smartPrompts = values.smartPrompts
        saved.announceDistance = values.announceDistance
        saved.announceElapsedTime = values.announceElapsedTime
        saved.announceAveragePace = values.announceAveragePace
        saved.announceClockTime = values.announceClockTime
        saved.announceHeartRate = values.announceHeartRate
        saved.announceRemainingRouteDistance = values.announceRemainingRouteDistance
        saved.announceEstimatedRemainingRouteTime = values.announceEstimatedRemainingRouteTime
        saved.announceCurrentWorkoutStep = values.announceCurrentWorkoutStep
        saved.announceRemainingStepTime = values.announceRemainingStepTime
        saved.announceRemainingStepDistance = values.announceRemainingStepDistance
        saved.duckOtherAudio = values.duckOtherAudio
        saved.guidanceQuietPeriodSeconds = values.guidanceQuietPeriodSeconds
        saved.voiceIdentifier = values.voiceIdentifier
        saved.speechRate = values.speechRate
        saved.speechVolume = values.speechVolume
        saved.speechStyle = values.speechStyle
        saved.announceWorkoutStart = values.announceWorkoutStart
        saved.announcePauseResume = values.announcePauseResume
        saved.announceWorkoutComplete = values.announceWorkoutComplete
        return saved
    }

    func configuration(
        routeDistanceMeters: Double? = nil,
        maximumHeartRateBPM: Double? = nil
    ) -> WatchAudioCoachConfiguration {
        var prompts = smartPrompts
        // An explicit per-workout HRmax overrides the profile estimate.
        // Otherwise use the athlete's configured maximum, never a guess.
        if prompts.maximumHeartRateBPM == nil,
           let maximumHeartRateBPM, maximumHeartRateBPM.isFinite,
           (100...240).contains(maximumHeartRateBPM) {
            prompts.maximumHeartRateBPM = maximumHeartRateBPM
        }
        // Keep standard distance/time cadence independently of custom groups.
        // For example, a new every-minute motivation rule must not disable an
        // athlete's existing every-kilometre distance/time announcement.
        // The Watch/iPhone rule schedulers already merge simultaneous events
        // and suppress duplicated metrics when a custom milestone is due.
        let standardCadenceEnabled = enabled
        return WatchAudioCoachConfiguration(
            enabled: enabled,
            language: language,
            distanceIntervalMeters:
                standardCadenceEnabled && distanceTriggerEnabled
                    ? distanceIntervalKilometers * 1_000
                    : nil,
            timeIntervalSeconds:
                standardCadenceEnabled && timeTriggerEnabled
                    ? Double(min(max(timeIntervalSeconds, 15), 7_200))
                    : nil,
            customRules: enabled && !customRules.isEmpty
                ? Array(customRules.prefix(20)) : nil,
            smartPrompts: enabled ? prompts : nil,
            announceDistance: enabled && announceDistance,
            announceElapsedTime:
                enabled && announceElapsedTime,
            announceAveragePace:
                enabled && announceAveragePace,
            announceClockTime:
                enabled && announceClockTime,
            announceHeartRate:
                enabled && announceHeartRate,
            announceRemainingRouteDistance:
                enabled && announceRemainingRouteDistance,
            announceEstimatedRemainingRouteTime:
                enabled &&
                announceEstimatedRemainingRouteTime,
            routeDistanceMeters: routeDistanceMeters,
            announceCurrentWorkoutStep:
                enabled && announceCurrentWorkoutStep,
            announceRemainingStepTime:
                enabled && announceRemainingStepTime,
            announceRemainingStepDistance:
                enabled && announceRemainingStepDistance,
            duckOtherAudio:
                duckOtherAudio,
            guidanceQuietPeriodSeconds:
                guidanceQuietPeriodSeconds,
            voiceIdentifier:
                voiceIdentifier,
            speechRate:
                Float(
                    min(
                        max(
                            speechRate,
                            0.35
                        ),
                        0.65
                    )
                ),
            speechVolume:
                Float(
                    min(
                        max(
                            speechVolume,
                            0.2
                        ),
                        1.0
                    )
                ),
            speechStyle: speechStyle,
            announceWorkoutStart:
                announceWorkoutStart,
            announcePauseResume:
                announcePauseResume,
            announceWorkoutComplete:
                announceWorkoutComplete
        )
    }
}

enum RunQuickStartMode: String, CaseIterable, Identifiable {
    case free
    case route
    case structured

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free:
            return ATHLTHLocalization.choose(
                english: "Free run", norwegian: "Fri løping"
            )
        case .route:
            return ATHLTHLocalization.choose(
                english: "Route", norwegian: "Rute"
            )
        case .structured:
            return ATHLTHLocalization.choose(
                english: "Workout", norwegian: "Treningsøkt"
            )
        }
    }

    var subtitle: String {
        switch self {
        case .free:
            return ATHLTHLocalization.choose(
                english: "Run freely without a route or target.",
                norwegian: "Løp fritt uten rute eller mål."
            )
        case .route:
            return ATHLTHLocalization.choose(
                english: "Use one of your saved routes.",
                norwegian: "Følg en av dine lagrede ruter."
            )
        case .structured:
            return ATHLTHLocalization.choose(
                english: "Choose a workout from the library.",
                norwegian: "Velg en økt fra treningsbiblioteket."
            )
        }
    }

    var icon: String {
        switch self {
        case .free: return "figure.run"
        case .route:
            return "point.topleft.down.to.point.bottomright.curvepath"
        case .structured: return "list.bullet.rectangle"
        }
    }
}

/// Basic running goals are projected to the same structured Watch/iPhone
/// timeline as the Advanced editor, not a separate workout engine.
enum ATHLTHBasicRunGoalKind: String, CaseIterable, Identifiable {
    case distance, time, pace, heartRateZone
    var id: String { rawValue }
    var title: String {
        switch self {
        case .distance: return ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse")
        case .time: return ATHLTHLocalization.choose(english: "Time", norwegian: "Tid")
        case .pace: return ATHLTHLocalization.choose(english: "Pace", norwegian: "Tempo")
        case .heartRateZone: return ATHLTHLocalization.choose(english: "HR zone", norwegian: "Pulssone")
        }
    }
}

enum RunEnvironment: String, CaseIterable, Identifiable, Codable, Hashable {
    case outdoor
    case indoor
    case treadmill

    var id: String { rawValue }

    /// A persisted planned session selects its own recording environment.
    /// Treadmill never implicitly inherits an outdoor route or GPS session.
    static func forPlannedSession(_ workout: PlannedSession?) -> RunEnvironment {
        guard let workout, workout.kind == .running else { return .outdoor }
        if workout.workoutCategory == "treadmill" { return .treadmill }
        if workout.workoutCategory == "indoor" { return .indoor }
        // Category is authoritative. Older recipes without a category
        // distinguish a treadmill by its incline target, not by GPS-off
        // alone: plain indoor running must remain plain indoor.
        if workout.resolvedWorkoutBlocks.contains(where: {
            $0.kind == .run && $0.isIndoor == true
        }) {
            return workout.resolvedWorkoutBlocks.contains(where: {
                $0.kind == .run && $0.treadmillInclinePercent != nil
            }) ? .treadmill : .indoor
        }
        return .outdoor
    }

    var title: String {
        switch self {
        case .outdoor:
            return ATHLTHLocalization.choose(
                english: "Outdoor",
                norwegian: "Ute"
            )
        case .indoor:
            return ATHLTHLocalization.choose(
                english: "Indoor", norwegian: "Innendørs"
            )
        case .treadmill:
            return ATHLTHLocalization.choose(
                english: "Treadmill",
                norwegian: "Tredemølle"
            )
        }
    }

    var subtitle: String {
        switch self {
        case .outdoor:
            return ATHLTHLocalization.choose(
                english: "GPS route, pace and elevation",
                norwegian: "GPS-rute, tempo og høyde"
            )
        case .indoor:
            return ATHLTHLocalization.choose(
                english: "Indoor without GPS", norwegian: "Uten GPS"
            )
        case .treadmill:
            return ATHLTHLocalization.choose(
                english: "Indoor run without GPS",
                norwegian: "Innendørs løping uten GPS"
            )
        }
    }

    var systemImage: String {
        switch self {
        case .outdoor: return "figure.run"
        case .indoor: return "building.2"
        case .treadmill: return "figure.run.treadmill"
        }
    }
}

struct RunQuickStartConfiguration {
    let mode: RunQuickStartMode
    let route: TrainingRoute?
    let workout: RunningWorkoutTemplate?
    let captureDevice: WorkoutCaptureDevice
    let environment: RunEnvironment
    let treadmillInclinePercent: Double?
    let audioCoach: WatchAudioCoachConfiguration
    let routeAlerts: WatchRouteAlertConfiguration
    let ghostTargetDurationSeconds: TimeInterval?
    let ghostUpdates: WatchGhostRaceAudioConfiguration?
    let autoPauseEnabled: Bool
    let spotifyPlaylist: SpotifyPlaylistReference?
    let spotifyAutoplay: Bool
    let friends: [SocialProfileCard]
    let socialMode:
        SocialWorkoutParticipationMode
    let gearIDs: Set<UUID>
    var petIDs: Set<UUID> = []
    var watchStartMode: WatchWorkoutStartMode = .immediate
    var routeWarmup: ATHLTHRouteWarmupConfiguration = .disabled
    var ghostPacingStrategy: GhostTargetPacingStrategy = .even
    var customWorkoutTitle: String? = nil
    /// Shared Plan timeline from the Advanced Quick Train composer.
    var advancedWorkout: PlannedSession? = nil

    var title: String {
        if mode == .structured, let advancedWorkout {
            return advancedWorkout.title
        }
        if let customWorkoutTitle,
           !customWorkoutTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customWorkoutTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch mode {
        case .free:
            return "Free Run"
        case .route:
            return route?.title ?? "Route Run"
        case .structured:
            return workout?.title ?? "Running Workout"
        }
    }
}

struct WalkQuickStartConfiguration {
    let captureDevice: WorkoutCaptureDevice
    let audioCoach: WatchAudioCoachConfiguration
    let autoPauseEnabled: Bool
    let spotifyPlaylist: SpotifyPlaylistReference?
    let spotifyAutoplay: Bool
    let friends: [SocialProfileCard]
    let socialMode:
        SocialWorkoutParticipationMode
    let gearIDs: Set<UUID>
    var petIDs: Set<UUID> = []
}

extension RunQuickStartConfiguration {
    func trainTogetherInvitePayload(
        savedRoutes: [TrainingRoute]
    ) -> SocialWorkoutInvitePayload {
        let resolvedRoute: TrainingRoute? = {
            guard environment == .outdoor else { return nil }
            if let route {
                return route
            }

            guard let routeID =
                    advancedWorkout?.routeID ?? workout?.routeID
            else {
                return nil
            }

            return savedRoutes.first {
                $0.id == routeID
            }
        }()

        var snapshot = PlannedSession(
            id: UUID(),
            title: title,
            kind: .running,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: environment == .outdoor
                ? (resolvedRoute?.id ?? workout?.routeID)
                : nil,
            exercises: [],
            notes: nil
        )
        // Preserve the same source recipe when Quick Run is relayed
        // through iPad or shared with training partners.
        if let advancedWorkout {
            snapshot.workoutBlocks = advancedWorkout.resolvedWorkoutBlocks
            snapshot.workoutCategory = advancedWorkout.workoutCategory
            snapshot.durationMinutes = advancedWorkout.durationMinutes
            snapshot.routeID = advancedWorkout.routeID
        } else {
            snapshot.runningWorkout = workout
            snapshot.runningWorkouts = workout.map { [$0] }
        }
        snapshot.audioCoachConfiguration =
            audioCoach
        snapshot.autoPauseEnabled =
            autoPauseEnabled
        snapshot.routeAlertConfiguration =
            routeAlerts
        snapshot.ghostTargetDurationSeconds =
            ghostTargetDurationSeconds
        snapshot.ghostUpdates =
            ghostUpdates

        return SocialWorkoutInvitePayload(
            workout: snapshot,
            route: resolvedRoute,
            routeAlerts: routeAlerts,
            participationMode:
                socialMode,
            maxParticipants:
                min(
                    max(
                        friends.count + 1,
                        2
                    ),
                    6
                )
        )
    }
}

extension WalkQuickStartConfiguration {
    var trainTogetherInvitePayload:
        SocialWorkoutInvitePayload {
        var snapshot = PlannedSession(
            id: UUID(),
            title:
                ATHLTHLocalization.choose(
                    english: "Walk",
                    norwegian: "Gåtur"
                ),
            kind: .walking,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
        snapshot.audioCoachConfiguration =
            audioCoach
        snapshot.autoPauseEnabled =
            autoPauseEnabled

        return SocialWorkoutInvitePayload(
            workout: snapshot,
            participationMode:
                socialMode,
            maxParticipants:
                min(
                    max(
                        friends.count + 1,
                        2
                    ),
                    6
                )
        )
    }
}

private struct QuickStartSpotifyCard: View {
    @EnvironmentObject private var spotify:
        SpotifyPlaybackStore

    var captureDevice: WorkoutCaptureDevice = .iPhone

    @Binding var playlist:
        SpotifyPlaylistReference?
    @Binding var autoplay: Bool
    let onChoose: () -> Void

    var body: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Spotify", systemImage: "music.note.list")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    if spotify.isRefreshingPlaylists {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if spotify.isConnected {
                    Button(action: onChoose) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Playlist",
                                        norwegian: "Spilleliste"
                                    )
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                                Text(
                                    playlist?.name ??
                                    ATHLTHLocalization.choose(
                                        english: "No playlist",
                                        norwegian: "Ingen spilleliste"
                                    )
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )
                                .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Start playlist with workout",
                            norwegian: "Start spilleliste med økten"
                        ),
                        isOn: $autoplay
                    )
                    .disabled(playlist == nil || captureDevice == .appleWatch)

                    if captureDevice == .appleWatch, playlist != nil {
                        Label(ATHLTHLocalization.choose(
                            english: "For a Watch workout, start Spotify on Apple Watch and choose your headphones there. ATHLTH will not resume an iPhone Spotify Connect speaker.",
                            norwegian: "Ved økt på Apple Watch starter du Spotify på klokken og velger hodetelefonene der. ATHLTH vil ikke starte en tidligere Spotify Connect-høyttaler fra iPhone."
                        ), systemImage: "applewatch")
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } else if spotify.isConfigured {
                    Button {
                        spotify.connect()
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Connect Spotify",
                                norwegian: "Koble til Spotify"
                            ),
                            systemImage: "link"
                        )
                    }

                    Text(
                        ATHLTHLocalization.choose(
                            english: "Connect Spotify to choose music for this workout.",
                            norwegian: "Koble til Spotify for å velge musikk til denne økten."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Spotify is not configured in this build.",
                            norwegian: "Spotify er ikke konfigurert i denne versjonen."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: playlist?.id) { _, playlistID in
            if playlistID == nil {
                autoplay = false
            }
        }
    }
}

private struct QuickStartAutoPauseCard: View {
    @Binding var preference: WorkoutAutoPausePreference
    let appDefaultEnabled: Bool

    var body: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Auto-pause",
                            norwegian: "Auto-pause"
                        ),
                        systemImage: "pause.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text(
                        appDefaultEnabled
                            ? ATHLTHLocalization.choose(english: "Default: On", norwegian: "Standard: På")
                            : ATHLTHLocalization.choose(english: "Default: Off", norwegian: "Standard: Av")
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                Picker(
                    ATHLTHLocalization.choose(
                        english: "Auto-pause",
                        norwegian: "Auto-pause"
                    ),
                    selection: $preference
                ) {
                    ForEach(WorkoutAutoPausePreference.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text(
                    ATHLTHLocalization.choose(
                        english: "Pauses the workout after sustained stillness and resumes when movement returns. Manual pause always takes priority.",
                        norwegian: "Pauser økten etter vedvarende stillstand og fortsetter når bevegelsen starter igjen. Manuell pause har alltid prioritet."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct QuickTrainingHeroCard: View {
    let imageName: String
    let title: String
    let subtitle: String?
    let icon: String
    let height: CGFloat

    init(
        imageName: String,
        title: String,
        subtitle: String? = nil,
        icon: String,
        height: CGFloat = 148
    ) {
        self.imageName = imageName
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.height = height
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .athlthBoundedFill()
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .clipped()

            LinearGradient(
                stops: [
                    .init(
                        color:
                            Color.black
                                .opacity(0.12),
                        location: 0
                    ),
                    .init(
                        color:
                            Color.black
                                .opacity(0.28),
                        location: 0.50
                    ),
                    .init(
                        color:
                            Color.black
                                .opacity(0.72),
                        location: 1
                    )
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.34),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            HStack(
                alignment: .bottom,
                spacing: 12
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    HStack(spacing: 7) {
                        Image(systemName: icon)
                            .font(
                                .system(
                                    size: 12,
                                    weight: .bold
                                )
                            )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "QUICK TRAIN",
                                norwegian:
                                    "QUICK TRAIN"
                            )
                        )
                        .font(
                            .system(
                                size: 9,
                                weight: .bold
                            )
                        )
                        .tracking(1.4)
                    }
                    .foregroundStyle(
                        Color.white
                            .opacity(0.86)
                    )

                    Text(title)
                        .font(
                            .system(
                                size: 25,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if let subtitle,
                       !subtitle.isEmpty {
                        Text(subtitle)
                            .font(
                                .subheadline
                                    .weight(.medium)
                            )
                            .foregroundStyle(
                                Color.white
                                    .opacity(0.86)
                            )
                            .lineLimit(2)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(17)
        }
        .frame(
            maxWidth: .infinity
        )
        .frame(height: height)
        .background(Color.black)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.18),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.10),
            radius: 18,
            y: 8
        )
    }
}

struct QuickStartWorkoutDeviceCard: View {
    @Binding var selection: WorkoutCaptureDevice
    let watchConnected: Bool
    let iPhoneEnabled: Bool
    let iPhoneSubtitle: String

    private var watchSelectable: Bool {
        ATHLTHDeviceRole.isIPad ||
            watchConnected
    }

    private var resolvedIPhoneSubtitle: String {
        ATHLTHDeviceRole.isIPad
            ? ATHLTHLocalization.choose(
                english:
                    "Send this workout to your signed-in iPhone.",
                norwegian:
                    "Send denne økten til iPhonen du er logget inn på."
            )
            : iPhoneSubtitle
    }

    private var watchSubtitle: String {
        if ATHLTHDeviceRole.isIPad {
            return ATHLTHLocalization.choose(
                english:
                    "Send this workout to Apple Watch through the paired iPhone. Start it later on Watch.",
                norwegian:
                    "Send økten til Apple Watch via den parede iPhonen. Start den senere på Watch."
            )
        }

        return watchConnected
            ? ATHLTHLocalization.choose(
                english:
                    "Send this workout to Apple Watch. Nothing starts until you press START on Watch.",
                norwegian:
                    "Send økten til Apple Watch. Ingenting starter før du trykker START på Watch."
            )
            : ATHLTHLocalization.choose(
                english:
                    "Finish Apple Watch setup in Settings to use this option.",
                norwegian:
                    "Fullfør Apple Watch-oppsettet i Innstillinger for å bruke dette valget."
            )
    }

    var body: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(title: "Workout device")

            VStack(spacing: 10) {
                deviceRow(
                    title: "iPhone",
                    subtitle: resolvedIPhoneSubtitle,
                    icon: "iphone",
                    selected: selection == .iPhone,
                    disabled: !iPhoneEnabled
                ) {
                    selection = .iPhone
                }

                deviceRow(
                    title: "Apple Watch",
                    subtitle: watchSubtitle,
                    icon: "applewatch",
                    selected: selection == .appleWatch,
                    disabled: !watchSelectable
                ) {
                    selection = .appleWatch
                }
            }
            .padding(.top, 10)
        }
    }

    private func deviceRow(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        disabled
                            ? Color.secondary
                            : selected
                                ? Color.white
                                : ATHLTHTheme.accent
                    )
                    .frame(width: 40, height: 40)
                    .background(
                        disabled
                            ? Color.primary.opacity(0.04)
                            : selected
                                ? ATHLTHTheme.accent
                                : ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            disabled
                                ? ATHLTHTheme.mutedText
                                : ATHLTHTheme.primaryText
                        )

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(
                    systemName:
                        selected
                            ? "checkmark.circle.fill"
                            : "circle"
                )
                .foregroundStyle(
                    selected && !disabled
                        ? ATHLTHTheme.accent
                        : Color.secondary.opacity(0.55)
                )
            }
            .padding(10)
            .background(
                selected && !disabled
                    ? ATHLTHTheme.accentSoft.opacity(0.55)
                    : Color.primary.opacity(0.02),
                in: RoundedRectangle(cornerRadius: 15)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.66 : 1)
    }
}

private struct PlannedQuickStartContextCard: View {
    let workout: PlannedSession

    var body: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 35, height: 35)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "FROM YOUR TRAINING PLAN",
                        norwegian: "FRA TRENINGSPLANEN"
                    ))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    Text(workout.title)
                        .font(.subheadline.weight(.semibold))
                    if let minutes = workout.durationMinutes,
                       minutes > 0 {
                        Label("\(minutes) min", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "iPhone workouts link to this plan after they are saved in Apple Health.",
                        norwegian: "iPhone-økter knyttes til planen når de er lagret i Apple Health."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Compact execution preview for the workout actually selected for a
/// Quick Run (or a planned workout launched directly from the calendar).
/// It does not infer targets or use a different workout as a fallback.
private struct ATHLTHRunQuickStartPlanPreview: View {
    let workout: RunningWorkoutTemplate?
    let plannedSession: PlannedSession?

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        if let workout {
            ATHLTHPlanSurface(density: .compact) {
                header(title: workout.title)
                HStack(spacing: 11) {
                    Label("\(workout.blocks.count) " + tr("phases", "deler"),
                          systemImage: "list.number")
                    if let seconds = workout.estimatedDurationSeconds {
                        Label("~\(Int((seconds / 60).rounded(.up))) min",
                              systemImage: "clock")
                    }
                    if let distance = workout.estimatedDistanceMeters {
                        Label(String(format: "~%.1f km", distance / 1_000),
                              systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                ForEach(Array(workout.blocks.prefix(5))) { block in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: block.kind == .work ? "figure.run" : "clock")
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .frame(width: 19)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(block.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            Text(blockDescription(block))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                }
                if workout.blocks.count > 5 {
                    Text(tr("Additional phases follow during the run.",
                            "Flere deler følger under økten."))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
        } else if let plannedSession {
            ATHLTHPlanSurface(density: .compact) {
                header(title: plannedSession.title)
                HStack(spacing: 12) {
                    Label("\(plannedSession.durationMinutes ?? 0) min",
                          systemImage: "clock")
                    Text(tr("From your training plan", "Fra treningsplanen"))
                }
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                let phases = (plannedSession.workoutBlocks ?? [])
                    .filter { $0.kind != .note }
                ForEach(Array(phases.prefix(5))) { block in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: block.kind.systemImage)
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.title)
                                .font(.caption.weight(.semibold))
                            if let target = block.targetText {
                                Text(target)
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5)
                }
                if phases.count > 5 {
                    Text(tr("More exercises in the full session.",
                            "Flere øvelser i den fullstendige økten."))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
        }
    }

    private func header(title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("YOUR SESSION", "DETTE SKAL DU GJØRE"))
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            Text(title)
                .font(.headline)
                .foregroundStyle(ATHLTHPlanDesign.ink)
        }
    }

    private func blockDescription(_ block: RunningWorkoutBlock) -> String {
        let step = block.work
        let length: String
        switch step.measure {
        case .distance:
            length = "\(Int(step.distanceMeters ?? 0)) m"
        case .time:
            length = "\(Int((step.durationSeconds ?? 0) / 60)) min"
        case .open:
            length = tr("Open", "Åpent")
        }
        var details = [block.repetitions > 1
                       ? "\(block.repetitions) × \(length)" : length]
        if let pace = step.intensity.paceMinSecondsPerKilometer, pace > 0 {
            details.append(String(format: "%.1f km/t", 3_600 / pace))
        }
        if let zone = step.intensity.heartRateZone {
            details.append(tr("HR zone", "Pulssone") + " \(zone)")
        }
        if let recovery = block.recovery {
            let pause = recovery.durationSeconds ?? 0
            details.append("\(Int(pause)) s " + tr("rest", "pause"))
        }
        return details.joined(separator: " · ")
    }
}

struct RunQuickStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var pets: ATHLTHPetStore
    @EnvironmentObject private var spotify: SpotifyPlaybackStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore

    let trainingDeviceProvider: TrainingDeviceProvider
    let watchConnected: Bool
    let plannedSession: PlannedSession?
    let onStart: (RunQuickStartConfiguration) async -> String?
    @State private var launchInProgress = false
    @State private var launchFailure: String?

    @State private var mode: RunQuickStartMode
    @State private var routeWarmup = ATHLTHRouteWarmupConfiguration.disabled
    @State private var selectedRoute: TrainingRoute?
    @State private var selectedWorkout: RunningWorkoutTemplate?
    @State private var advancedWorkout: PlannedSession?
    @State private var basicGoalSelected = false
    @State private var basicGhostSelected = false
    @State private var basicGoals: Set<ATHLTHBasicRunGoalKind> = [.distance]
    @State private var basicGoalDistanceKilometers = 5
    @State private var basicGoalTimeMinutes = 30
    @State private var basicGoalPaceSecondsPerKilometer = 360
    @State private var basicGoalHeartRateZone = 2
    @State private var basicGoalWorkoutID = UUID()
    @State private var basicGhostTargetMinutes = 40
    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var socialMode:
        SocialWorkoutParticipationMode =
            .physical
    @State private var selectedGearIDs: Set<UUID> = []
    @State private var selectedPetIDs: Set<UUID> = []
    @State private var captureDevice: WorkoutCaptureDevice
    @State private var watchStartMode: WatchWorkoutStartMode = .immediate
    @State private var environment: RunEnvironment = .outdoor
    @State private var quickWorkoutName = ""
    @State private var quickDisplayDate = Date()
    @State private var pendingStartDate: Date?
    @State private var pendingStartDevice: WorkoutCaptureDevice?
    @State private var delayedStartTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var routeLocationProbe =
        QuickStartRouteLocationProbe()

    init(
        trainingDeviceProvider: TrainingDeviceProvider,
        watchConnected: Bool,
        initialRoute: TrainingRoute? = nil,
        initialWorkout:
            RunningWorkoutTemplate? = nil,
        plannedSession: PlannedSession? = nil,
        onStart: @escaping (RunQuickStartConfiguration) async -> String?
    ) {
        self.trainingDeviceProvider = trainingDeviceProvider
        self.watchConnected = watchConnected
        self.plannedSession = plannedSession
        self.onStart = onStart

        // Planned indoor and treadmill workouts must never inherit GPS
        // even when launched from an existing route or interval card.
        let plannedEnvironment = RunEnvironment.forPlannedSession(plannedSession)
        let initialMode: RunQuickStartMode =
            initialWorkout != nil ? .structured :
            (initialRoute != nil && plannedEnvironment == .outdoor ? .route : .free)

        _environment = State(initialValue: plannedEnvironment)
        _mode = State(initialValue: initialMode)
        _selectedRoute = State(
            initialValue: plannedEnvironment == .outdoor ? initialRoute : nil
        )
        _selectedWorkout = State(
            initialValue: initialWorkout
        )
        // A quick workout started from iPhone must never silently
        // jump to Apple Watch. Start with iPhone selected and let the user
        // explicitly choose Apple Watch for this workout.
        _captureDevice = State(
            initialValue: .iPhone
        )
    }

    @State private var showingRoutes = false
    @State private var showingRunningLibrary = false
    @State private var showingDetailedWorkoutBuilder = false

    @State private var audioCoachDraft = AudioCoachDraft()
    @State private var routeGuardianDraft =
        RouteGuardianDraft()
    @State private var ghostDraft =
        GhostQuickStartDraft()
    @State private var didLoadAudioCoachDefaults = false
    @State private var didLoadGuidanceDefaults = false
    @State private var didResolveSetupMode = false
    @State private var isAdvancedSetup = false
    @State private var autoPausePreference:
        WorkoutAutoPausePreference = .appDefault
    @State private var selectedSpotifyPlaylist:
        SpotifyPlaylistReference?
    @State private var spotifyAutoplay = false
    @State private var showingSpotifyPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: isAdvancedSetup ? 16 : 12) {
                    // Identical details card in Basic and Advanced.
                    // Quick Train always starts now, so its time is read-only.
                    advancedWorkoutDetailsCard
                    if isAdvancedSetup {
                        modeCard
                    } else {
                        ATHLTHRunBasicSetupView(
                            workoutName: $quickWorkoutName,
                            mode: $mode,
                            environment: $environment,
                            date: $quickDisplayDate,
                            selectedRouteTitle: selectedRoute?.title,
                            selectedWorkoutTitle: selectedWorkout?.title,
                            onChooseRoute: { showingRoutes = true },
                            onChooseWorkout: { showingRunningLibrary = true },
                            onChooseGoal: {
                                basicGoalSelected = true
                                basicGhostSelected = false
                                mode = .structured
                                advancedWorkout = nil
                                selectedWorkout = nil
                            },
                            onChooseGhost: {
                                basicGoalSelected = false
                                basicGhostSelected = true
                                environment = .outdoor
                                mode = .route
                                ghostDraft.enabled = true
                                ghostDraft.setTargetTimeText(
                                    GhostTargetTimeFormatter.string(
                                        TimeInterval(basicGhostTargetMinutes * 60)
                                    ),
                                    distanceKilometers: guidanceRoute?.distanceKilometers
                                )
                                if selectedRoute == nil { showingRoutes = true }
                            },
                            onChooseStandardMode: {
                                basicGoalSelected = false
                                basicGhostSelected = false
                            },
                            isGoalSelected: basicGoalSelected,
                            isGhostSelected: basicGhostSelected,
                            audioCoachEnabled: session.canAccess(.audioCoach)
                                ? $audioCoachDraft.enabled : nil
                        )
                    }

                    if let plannedSession {
                        PlannedQuickStartContextCard(workout: plannedSession)
                        ATHLTHRunQuickStartPlanPreview(
                            workout: nil, plannedSession: plannedSession
                        )
                    }

                    if basicGoalSelected {
                        basicGoalSetupCard
                    } else {
                        if mode == .route || mode == .structured {
                            if isAdvancedSetup {
                                selectionCard
                            } else {
                                basicSelectedContent
                            }
                        }
                        if basicGhostSelected {
                            basicGhostSetupCard
                        }
                    }

                    if mode == .route, selectedRoute != nil {
                        if isAdvancedSetup {
                            ATHLTHRouteWarmupCard(configuration: $routeWarmup)
                        } else {
                            DisclosureGroup {
                                ATHLTHRouteWarmupCard(configuration: $routeWarmup)
                            } label: {
                                Label(ATHLTHLocalization.choose(
                                    english: "Optional warm-up",
                                    norwegian: "Valgfri oppvarming"
                                ), systemImage: "timer")
                                .font(.subheadline.weight(.medium))
                                .frame(minHeight: 44)
                            }
                            .tint(ATHLTHTrainDesign.bronze)
                        }
                    }

                    if isAdvancedSetup {
                        quickRunGuidanceCard
                        ATHLTHPlanSurface(ghost: false, density: .compact) {
                            VStack(alignment: .leading, spacing: 10) {
                                WorkoutFriendPicker(selectedFriendIDs: $selectedFriendIDs)
                                if !selectedFriendIDs.isEmpty {
                                    Divider()
                                    WorkoutSocialModePicker(mode: $socialMode)
                                }
                            }
                        }
                    }

                    ATHLTHQuickWorkoutPetPicker(selectedPetIDs: $selectedPetIDs)

                    if isAdvancedSetup {
                        VStack(spacing: 12) {
                            WorkoutGearSelectionCard(
                                selectedGearIDs: $selectedGearIDs,
                                activity: .running
                            )

                            if environment == .outdoor {
                                QuickStartAutoPauseCard(
                                    preference: $autoPausePreference,
                                    appDefaultEnabled:
                                        settings.autoPauseOutdoorWorkouts
                                )
                            }

                            QuickStartSpotifyCard(
                                captureDevice: captureDevice,
                                playlist:
                                    $selectedSpotifyPlaylist,
                                autoplay:
                                    $spotifyAutoplay
                            ) {
                                showingSpotifyPicker = true
                            }

                        }
                        .transition(
                            .opacity
                                .combined(
                                    with: .move(
                                        edge: .top
                                    )
                                )
                        )
                    }

                }
                .padding()
            }
            // Use the exact canvas from Training Plan, not the legacy
            // Quick Train gradient.
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .safeAreaInset(
                edge: .bottom,
                spacing: 0
            ) {
                runStickyStartBar
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Start Run",
                    norwegian: "Start løpeøkt"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    runSetupModeButton
                }
            }
            .sheet(isPresented: $showingRoutes) {
                NavigationStack {
                    SavedRoutesView(
                        selectionTitle: "Choose Route"
                    ) { route in
                        selectedRoute = route
                        showingRoutes = false
                    }
                }
            }
            .sheet(isPresented: $showingRunningLibrary) {
                NavigationStack {
                    RunningWorkoutLibraryView(
                        selectionTitle: "Choose Workout"
                    ) { workout in
                        advancedWorkout = nil
                        selectedWorkout = workout
                        showingRunningLibrary = false
                    }
                }
            }
            .sheet(isPresented: $showingDetailedWorkoutBuilder) {
                // Exactly the same advanced studio and ordered timeline as
                // Plan -> From Scratch -> Running, not the legacy interval
                // composer and not a second workout execution engine.
                WorkoutTemplateBuilderView(
                    initialTitle: basicGoalSelected
                        ? basicGoalWorkout.title
                        : advancedWorkout?.title ??
                          selectedWorkout?.title ?? quickWorkoutName,
                    initialBlocks: (basicGoalSelected
                        ? basicGoalWorkout.resolvedWorkoutBlocks
                        : advancedWorkout?.resolvedWorkoutBlocks) ??
                        selectedWorkout.map {
                            ATHLTHQuickRunTimelineAdapter.editorBlocks(from: $0)
                        } ?? [],
                    initialRouteID: basicGoalSelected ? nil :
                        (advancedWorkout?.routeID ?? selectedWorkout?.routeID),
                    draftContext: "quick-run-advanced",
                    initialActivity: .running,
                    initialStudioAdvanced: true,
                    onAddStandalone: { workout in
                        if let issue = ATHLTHQuickRunTimelineAdapter.validationError(
                            for: workout
                        ) {
                            launchFailure = issue
                            return false
                        }
                        advancedWorkout = workout
                        basicGoalSelected = false
                        basicGhostSelected = false
                        selectedWorkout = nil
                        quickWorkoutName = workout.title
                        environment = ATHLTHQuickRunTimelineAdapter.environment(
                            for: workout
                        )
                        launchFailure = nil
                        mode = .structured
                        return true
                    },
                    onValidateSave: {
                        ATHLTHQuickRunTimelineAdapter.validationError(for: $0)
                    },
                    saveButtonTitle: ATHLTHLocalization.choose(
                        english: "Use in Quick Train",
                        norwegian: "Bruk i Quick Train"
                    )
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingSpotifyPicker) {
                SpotifyPlaylistPickerView(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Run Playlist",
                            norwegian: "Spilleliste for løping"
                        ),
                    selection:
                        $selectedSpotifyPlaylist
                )
                .onDisappear {
                    spotifyAutoplay =
                        selectedSpotifyPlaylist != nil
                }
            }
            .task {
                if let invited = social.takePreparedQuickTrainFriends() {
                    selectedFriendIDs = invited
                }

                if !didResolveSetupMode {
                    isAdvancedSetup =
                        settings
                            .resolvedAdvancedSetup(
                                for: .running
                            )
                    didResolveSetupMode = true
                }

                if !didLoadAudioCoachDefaults {
                    audioCoachDraft.load(from: settings)
                    // Plan/individual workout choices supersede global defaults.
                    // Never write these session-scoped overrides back to Settings.
                    if let savedCoach = plannedSession?.audioCoachConfiguration {
                        audioCoachDraft.load(configuration: savedCoach)
                    }
                    didLoadAudioCoachDefaults = true
                }

                // Quick workouts are session-local. Re-read the
                // Settings default every time this sheet is presented so a
                // playlist chosen for the previous workout is never carried
                // into a new one unless it is explicitly the global default.
                selectedSpotifyPlaylist =
                    settings.spotifyDefaultPlaylist
                spotifyAutoplay =
                    settings.spotifyAutoplayLinkedPlaylists &&
                    selectedSpotifyPlaylist != nil

                if spotify.isConnected &&
                    spotify.playlists.isEmpty {
                    await spotify.refreshPlaylists()
                }

                if !didLoadGuidanceDefaults {
                    routeGuardianDraft.load(
                        from: settings
                    )
                    ghostDraft.load(
                        route: guidanceRoute,
                        settings: settings
                    )
                    didLoadGuidanceDefaults = true
                }

                if social.trainingPartners.isEmpty {
                    await social.refresh()
                }

                if gear.items.isEmpty {
                    await gear.refresh()
                }

                if selectedGearIDs.isEmpty {
                    selectedGearIDs =
                        gear.initialGearSelection(
                            for: .running
                        )
                }

                routeLocationProbe.refresh()
            }
            .onDisappear {
                cancelPendingQuickRun()
                guard captureDevice == .iPhone,
                      phoneWorkout.active != nil,
                      !phoneWorkout.isUserMinimized
                else {
                    return
                }

                Task { @MainActor in
                    await Task.yield()
                    try? await Task.sleep(
                        for: .milliseconds(120)
                    )
                    phoneWorkout.presentWorkout()
                }
            }
            .onChange(
                of: selectedRoute?.id
            ) { _, _ in
                routeLocationProbe.refresh()
                ghostDraft.load(
                    route: guidanceRoute,
                    settings: settings
                )
                if basicGhostSelected, guidanceRoute != nil {
                    ghostDraft.enabled = true
                    ghostDraft.setTargetTimeText(
                        GhostTargetTimeFormatter.string(
                            TimeInterval(basicGhostTargetMinutes * 60)
                        ),
                        distanceKilometers: guidanceRoute?.distanceKilometers
                    )
                }
            }
            .onChange(
                of: selectedWorkout?.id
            ) { _, _ in
                ghostDraft.load(
                    route: guidanceRoute,
                    settings: settings
                )
            }
            .onChange(of: scenePhase) { _, _ in
                firePendingQuickRun()
            }
            .onChange(of: mode) { _, selected in
                if selected != .structured { basicGoalSelected = false }
                if selected != .route { basicGhostSelected = false }
            }
            .onChange(of: basicGhostTargetMinutes) { _, minutes in
                guard basicGhostSelected else { return }
                ghostDraft.setTargetTimeText(
                    GhostTargetTimeFormatter.string(
                        TimeInterval(minutes * 60)
                    ),
                    distanceKilometers: guidanceRoute?.distanceKilometers
                )
            }
            .onChange(of: environment) { _, newValue in
                if newValue != .outdoor {
                    basicGhostSelected = false
                }
                if newValue != .outdoor,
                   mode == .route {
                    mode = .free
                    selectedRoute = nil
                }

                if newValue != .outdoor {
                    routeGuardianDraft.enabled = false
                    ghostDraft.enabled = false
                    autoPausePreference = .off
                }
            }
        }
    }

    /// Advanced reuses the Basic workout-details hierarchy, but keeps
    /// its full mode and coaching tools below the compact identity card.
    private var advancedWorkoutDetailsCard: some View {
        ATHLTHWorkoutDetailsCard(
            activityTitle: ATHLTHLocalization.choose(
                english: "Running", norwegian: "Løping"
            ),
            symbol: "figure.run",
            name: $quickWorkoutName
        ) {
            ATHLTHRunEnvironmentDetailRow(environment: $environment)
            if environment == .treadmill,
               let prior = phoneWorkout.lastTreadmillSpeedReference {
                Label(
                    ATHLTHLocalization.format(
                        english: "Last treadmill speed: %.1f km/h (reference only)",
                        norwegian: "Siste møllehastighet: %.1f km/t (kun referanse)",
                        prior.speed
                    ),
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTrainDesign.bronze)
            }
        }
    }

    private var runSetupModeButton: some View {
        Button {
            let nextMode =
                !isAdvancedSetup
            isAdvancedSetup =
                nextMode
            settings.recordAdvancedSetup(
                nextMode,
                for: .running
            )
        } label: {
            HStack(spacing: 6) {
                Image(
                    systemName:
                        isAdvancedSetup
                            ? "slider.horizontal.3"
                            : "bolt.fill"
                )
                .font(
                    .system(
                        size: 11,
                        weight: .semibold
                    )
                )

                Text(
                    isAdvancedSetup
                        ? ATHLTHLocalization.choose(
                            english: "Advanced",
                            norwegian: "Avansert"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Basic", norwegian: "Enkel"
                        )
                )
                .font(
                    .caption
                        .weight(.bold)
                )
            }
            .foregroundStyle(
                isAdvancedSetup ? Color.white : ATHLTHPlanDesign.ink
            )
            .padding(.horizontal, 11)
            .frame(minHeight: 36)
            .background(
                isAdvancedSetup
                    ? ATHLTHTheme.accentDeep
                    : ATHLTHPlanDesign.selectedSurface,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(ATHLTHPlanDesign.outline, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            ATHLTHLocalization.choose(
                english:
                    "Switch run setup mode",
                norwegian:
                    "Bytt oppsettsmodus for løpeøkt"
            )
        )
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Run type", norwegian: "Løpetype"
                ))
                .font(.headline)
                .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer()
                Text(ATHLTHLocalization.choose(
                    english: "Choose one", norwegian: "Velg én"
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }

            ForEach(RunQuickStartMode.allCases) { option in
                let unavailable = environment != .outdoor && option == .route

                ATHLTHPlanSelectionCard(
                    title: option.title,
                    subtitle: option.subtitle,
                    symbol: option.icon,
                    selected: mode == option,
                    accent: ATHLTHPlanDesign.accentInk
                ) {
                    guard !unavailable else { return }
                    mode = option
                }
                .disabled(unavailable)
                .opacity(unavailable ? 0.48 : 1)
            }
        }
    }

    private var basicSelectedContent: some View {
        HStack(spacing: 10) {
            Image(systemName: mode == .route ? "map" : "list.bullet.rectangle")
                .foregroundStyle(ATHLTHTrainDesign.bronze)
            VStack(alignment: .leading, spacing: 3) {
                Text(mode == .route
                    ? selectedRoute?.title ?? ATHLTHLocalization.choose(
                        english: "Choose route", norwegian: "Velg rute"
                      )
                    : advancedWorkout?.title ??
                      selectedWorkout?.title ?? ATHLTHLocalization.choose(
                        english: "Choose workout", norwegian: "Velg treningsøkt"
                      ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .lineLimit(1)
                if mode == .route, let selectedRoute {
                    Text(String(format: "%.1f km", selectedRoute.distanceKilometers))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(ATHLTHLocalization.choose(
                english: "Change", norwegian: "Endre"
            )) {
                if mode == .route { showingRoutes = true }
                else { showingRunningLibrary = true }
            }
            .buttonStyle(.bordered)
            .tint(ATHLTHTrainDesign.bronze)
        }
        .padding(12)
        .athlthTrainPaper()
    }

    @ViewBuilder
    private var selectionCard: some View {
        switch mode {
        case .free:
            ATHLTHPlanSurface(density: .compact) {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(ATHLTHTheme.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            environment == .treadmill
                                ? ATHLTHLocalization.choose(
                                    english: "Indoor treadmill run",
                                    norwegian: "Innendørs tredemølleøkt"
                                )
                                : "No destination. No target."
                        )
                        .font(.subheadline.weight(.semibold))
                        Text(
                            environment == .treadmill
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "ATHLTH records time and the incline you selected. GPS and route tracking stay off indoors.",
                                    norwegian:
                                        "ATHLTH registrerer tid og valgt stigning. GPS og rutesporing er av innendørs."
                                )
                                : "ATHLTH records your run, GPS route, time, distance and available heart-rate data."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }

        case .route:
            ATHLTHPlanSurface(density: .compact) {
                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    if let selectedRoute,
                       selectedRoute
                        .coordinates
                        .count >= 2 {
                        ZStack(
                            alignment: .topLeading
                        ) {
                            RouteMapSnapshotThumbnail(
                                route: selectedRoute,
                                height: 112
                            )

                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Selected route",
                                    norwegian: "Valgt rute"
                                ),
                                systemImage:
                                    "point.3.connected.trianglepath.dotted"
                            )
                            .font(
                                .caption2
                                    .weight(.bold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )
                            .padding(
                                .horizontal,
                                9
                            )
                            .padding(
                                .vertical,
                                6
                            )
                            .background(
                                .ultraThinMaterial,
                                in: Capsule()
                            )
                            .padding(9)
                        }
                    }

                    HStack(
                        alignment: .center,
                        spacing: 12
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: 5
                        ) {
                            HStack(
                                spacing: 7
                            ) {
                                Image(
                                    systemName:
                                        "figure.run"
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .vitality
                                )

                                Text(
                                    selectedRoute?
                                        .title ??
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Choose a saved route",
                                            norwegian:
                                                "Velg en lagret rute"
                                        )
                                )
                                .font(.headline)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .primaryText
                                )
                                .lineLimit(2)

                                if let selectedRoute {
                                    Image(
                                        systemName:
                                            selectedRouteVisibilityIcon(
                                                selectedRoute
                                                    .visibility
                                            )
                                    )
                                    .font(
                                        .caption2
                                            .weight(
                                                .bold
                                            )
                                    )
                                    .foregroundStyle(
                                        selectedRouteVisibilityTint(
                                            selectedRoute
                                                .visibility
                                        )
                                    )
                                }
                            }

                            if let selectedRoute {
                                HStack(
                                    spacing: 8
                                ) {
                                    Text(
                                        String(
                                            format:
                                                "%.1f km",
                                            selectedRoute
                                                .distanceKilometers
                                        )
                                    )

                                    if let start =
                                            selectedRoute
                                                .startName,
                                       !start.isEmpty,
                                       let end =
                                            selectedRoute
                                                .endName,
                                       !end.isEmpty {
                                        Text("·")
                                        Text(
                                            "\(start) → \(end)"
                                        )
                                        .lineLimit(1)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                            } else {
                                Text(
                                    session
                                        .savedRoutes
                                        .isEmpty
                                        ? ATHLTHLocalization
                                            .choose(
                                                english:
                                                    "You do not have any saved routes yet.",
                                                norwegian:
                                                    "Du har ingen lagrede ruter ennå."
                                            )
                                        : ATHLTHLocalization
                                            .format(
                                                english:
                                                    "%d routes available",
                                                norwegian:
                                                    "%d ruter tilgjengelig",
                                                session
                                                    .savedRoutes
                                                    .count
                                            )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                            }
                        }

                        Spacer(
                            minLength: 8
                        )

                        Button {
                            showingRoutes = true
                        } label: {
                            Text(
                                selectedRoute == nil
                                    ? ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Choose",
                                            norwegian:
                                                "Velg"
                                        )
                                    : ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Change",
                                            norwegian:
                                                "Endre"
                                        )
                            )
                        }
                        .buttonStyle(
                            .borderedProminent
                        )
                        .controlSize(.small)
                        .tint(
                            ATHLTHTheme
                                .accentDeep
                        )
                    }

                    if let distance =
                            distanceToSelectedRouteStart,
                       distance > 250 {
                        Divider()

                        HStack(
                            alignment: .top,
                            spacing: 10
                        ) {
                            Image(
                                systemName:
                                    "location.circle.fill"
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .premiumGold
                            )

                            VStack(
                                alignment: .leading,
                                spacing: 4
                            ) {
                                Text(
                                    routeStartDistanceText(
                                        distance
                                    )
                                )
                                .font(
                                    .subheadline
                                        .weight(
                                            .semibold
                                        )
                                )

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "You can start anyway, but ATHLTH will mark route progress when you reach the course.",
                                        norwegian:
                                            "Du kan starte uansett, men ATHLTH registrerer rutefremdrift når du når løypen."
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )

                                Button {
                                    openDirectionsToRouteStart()
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Directions to start",
                                            norwegian:
                                                "Veibeskrivelse til start"
                                        ),
                                        systemImage:
                                            "arrow.triangle.turn.up.right.diamond.fill"
                                    )
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .padding(.top, 3)
                            }

                            Spacer(
                                minLength: 0
                            )
                        }
                    }

                    if session
                        .savedRoutes
                        .isEmpty {
                        NavigationLink {
                            RunRouteBuilderView()
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Create Route",
                                    norwegian:
                                        "Opprett rute"
                                ),
                                systemImage:
                                    "plus"
                            )
                        }
                    }
                }
            }
            .athlthLightweightCardChrome()

        case .structured:
            ATHLTHPlanSurface(density: .compact) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            advancedWorkout?.title ??
                                selectedWorkout?.title ??
                                "Choose a running workout"
                        )
                        .font(.headline)

                        Text(
                            advancedWorkout.map {
                                ATHLTHLocalization.choose(
                                    english: "\($0.resolvedWorkoutBlocks.count) planned phases",
                                    norwegian: "\($0.resolvedWorkoutBlocks.count) planlagte øktdeler"
                                )
                            } ??
                            selectedWorkout?.summary ??
                                "\(runningLibrary.allTemplates.count) structured workouts available"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    }

                    Spacer()

                    Button {
                        showingRunningLibrary = true
                    } label: {
                        Text(
                            selectedWorkout == nil && advancedWorkout == nil
                                ? "Choose"
                                : "Change"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(ATHLTHTheme.accent)
                }

                Button {
                    showingDetailedWorkoutBuilder = true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: selectedWorkout == nil && advancedWorkout == nil
                                ? "Build detailed session" : "Customize every phase",
                            norwegian: selectedWorkout == nil && advancedWorkout == nil
                                ? "Bygg detaljert økt" : "Tilpass hver enkelt del"
                        ),
                        systemImage: "slider.horizontal.3"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.top, 9)

                if let advancedWorkout {
                    ATHLTHRunQuickStartPlanPreview(
                        workout: nil, plannedSession: advancedWorkout
                    )
                } else if let workout = selectedWorkout {
                    ATHLTHRunQuickStartPlanPreview(
                        workout: workout, plannedSession: nil
                    )
                    Label(
                        ATHLTHLocalization.counted(
                                workout.blocks.count,
                                englishSingular: "block",
                                englishPlural: "blocks",
                                norwegianSingular: "blokk",
                                norwegianPlural: "blokker"
                            ) +
                        workout.estimatedDistanceMeters.map {
                            String(
                                format: " · %.1f km",
                                $0 / 1_000
                            )
                        }.orEmpty,
                        systemImage: workout.type.systemImage
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 9)
                }
            }
        }
    }

    private var runStickyStartBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let launchFailure {
                ATHLTHQuickWatchLaunchNotice(message: launchFailure) {
                    self.launchFailure = nil
                }
                .padding(.horizontal, 12)
            }
            if launchInProgress {
                ProgressView(ATHLTHLocalization.choose(
                    english: "Starting workout…", norwegian: "Starter treningsøkten…"
                ))
                .font(.caption)
                .padding(.horizontal, 12)
            }
            ATHLTHQuickRunStartFooter(
                watchAvailable: watchConnected || ATHLTHDeviceRole.isIPad,
                canStart: canSubmitQuickRun(captureDevice: .iPhone),
                starting: launchInProgress,
                scheduledDate: pendingStartDate,
                onIPhoneNow: {
                    cancelPendingQuickRun()
                    captureDevice = .iPhone
                    watchStartMode = .immediate
                    submitQuickRun(captureDevice: .iPhone)
                },
                onWatchNow: {
                    cancelPendingQuickRun()
                    captureDevice = .appleWatch
                    watchStartMode = .immediate
                    submitQuickRun(captureDevice: .appleWatch)
                },
                onWatchCountDown: {
                    cancelPendingQuickRun()
                    captureDevice = .appleWatch
                    watchStartMode = .afterThirtySeconds
                    submitQuickRun(captureDevice: .appleWatch)
                },
                onWatchManual: {
                    cancelPendingQuickRun()
                    captureDevice = .appleWatch
                    watchStartMode = .onWatch
                    submitQuickRun(captureDevice: .appleWatch)
                },
                onDelay: { device, seconds in
                    scheduleQuickRun(device: device, after: seconds)
                },
                onCancelDelay: cancelPendingQuickRun
            )
        }
    }

    private func cancelPendingQuickRun() {
        delayedStartTask?.cancel()
        delayedStartTask = nil
        pendingStartDate = nil
        pendingStartDevice = nil
    }

    private func scheduleQuickRun(
        device: WorkoutCaptureDevice, after seconds: Int
    ) {
        guard seconds > 0, canSubmitQuickRun(captureDevice: device) else {
            return
        }
        cancelPendingQuickRun()
        pendingStartDevice = device
        pendingStartDate = Date().addingTimeInterval(TimeInterval(seconds))
        delayedStartTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, scenePhase == .active else { return }
            firePendingQuickRun()
        }
    }

    private func firePendingQuickRun() {
        guard !launchInProgress, let date = pendingStartDate,
              date <= Date(), let device = pendingStartDevice,
              scenePhase == .active else { return }
        cancelPendingQuickRun()
        captureDevice = device
        watchStartMode = .immediate
        quickDisplayDate = Date()
        submitQuickRun(captureDevice: device)
    }

    private var basicGoalWorkout: PlannedSession {
        ATHLTHBasicRunGoalRecipe.make(
            id: basicGoalWorkoutID,
            title: quickWorkoutName,
            kind: basicGoals.contains(.distance) ? .distance
                : (basicGoals.contains(.time) ? .time
                    : (basicGoals.contains(.pace) ? .pace : .heartRateZone)),
            distanceKilometers: basicGoalDistanceKilometers,
            timeMinutes: basicGoalTimeMinutes,
            paceSecondsPerKilometer: basicGoalPaceSecondsPerKilometer,
            heartRateZone: basicGoalHeartRateZone,
            environment: environment,
            selectedGoals: basicGoals
        )
    }

    private var basicGoalSetupCard: some View {
        ATHLTHPlanSurface(density: .compact) {
            VStack(alignment: .leading, spacing: 12) {
                Label(ATHLTHLocalization.choose(
                    english: "Your running goal", norwegian: "Ditt løpemål"
                ), systemImage: "target")
                    .font(.headline)
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Text(ATHLTHLocalization.choose(
                    english: "Combine goals", norwegian: "Kombiner mål"
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(ATHLTHBasicRunGoalKind.allCases) { kind in
                        let selected = basicGoals.contains(kind)
                        Button {
                            if selected {
                                // Always retain at least one goal.
                                if basicGoals.count > 1 { basicGoals.remove(kind) }
                            } else {
                                basicGoals.insert(kind)
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: selected
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                                Text(kind.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 46)
                            .background(selected
                                ? ATHLTHTrainDesign.paleGold.opacity(0.65)
                                : Color.white,
                                in: RoundedRectangle(cornerRadius: 13))
                            .overlay {
                                RoundedRectangle(cornerRadius: 13)
                                    .strokeBorder(
                                        ATHLTHTrainDesign.bronze.opacity(
                                            selected ? 0.55 : 0.16),
                                        lineWidth: selected ? 1.2 : 0.8)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
                if basicGoals.contains(.distance) {
                    Stepper(
                        "\(basicGoalDistanceKilometers) km",
                        value: $basicGoalDistanceKilometers, in: 1...42
                    )
                }
                if basicGoals.contains(.time) {
                    Stepper(
                        "\(basicGoalTimeMinutes) min",
                        value: $basicGoalTimeMinutes, in: 5...240, step: 5
                    )
                }
                if basicGoals.contains(.pace) {
                    Stepper(
                        String(format: "%d:%02d min/km",
                               basicGoalPaceSecondsPerKilometer / 60,
                               basicGoalPaceSecondsPerKilometer % 60),
                        value: $basicGoalPaceSecondsPerKilometer,
                        in: 180...900, step: 5
                    )
                }
                if basicGoals.contains(.heartRateZone) {
                    Stepper(
                        ATHLTHLocalization.choose(
                            english: "Heart rate zone", norwegian: "Pulssone"
                        ) + " \(basicGoalHeartRateZone)",
                        value: $basicGoalHeartRateZone, in: 1...5
                    )
                }
                if basicGoals.contains(.distance) && basicGoals.contains(.time) {
                    Text(ATHLTHLocalization.choose(
                        english: "Distance completes the run phase; time is a target to aim for.",
                        norwegian: "Distanse avslutter løpedelen. Tiden er målet du prøver å nå."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                } else if !basicGoals.contains(.distance) && !basicGoals.contains(.time) {
                    Text(ATHLTHLocalization.choose(
                        english: "Open run: finish when ready. Audio Coach helps maintain your targets.",
                        norwegian: "Åpen økt: avslutt når du ønsker. Audio Coach hjelper deg å holde målene."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                if isAdvancedSetup {
                    Button {
                        showingDetailedWorkoutBuilder = true
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Edit in workout builder",
                            norwegian: "Rediger i øktbyggeren"
                        ), systemImage: "slider.horizontal.3")
                    }
                    .font(.subheadline.weight(.medium))
                    .tint(ATHLTHTrainDesign.bronze)
                }
            }
        }
    }

    private var basicGhostSetupCard: some View {
        ATHLTHPlanSurface(density: .compact) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Ghost Race", systemImage: "figure.run.circle")
                    .font(.headline)
                if selectedRoute == nil {
                    Button {
                        showingRoutes = true
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Choose a route",
                            norwegian: "Velg rute"
                        ), systemImage: "map")
                    }
                } else {
                    Stepper(
                        ATHLTHLocalization.choose(
                            english: "Target finish", norwegian: "Måltid"
                        ) + ": \(basicGhostTargetMinutes) min",
                        value: $basicGhostTargetMinutes, in: 5...360, step: 5
                    )
                    Text(ATHLTHLocalization.choose(
                        english: "The Ghost starts on the saved outdoor course. Change the target in Advanced for finer pacing.",
                        norwegian: "Ghost starter på valgt utendørsrute. I Avansert kan du justere tempoet mer detaljert."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
        }
    }

    private func canSubmitQuickRun(
        captureDevice:
            WorkoutCaptureDevice
    ) -> Bool {
        if captureDevice == .appleWatch,
           !watchConnected,
           !ATHLTHDeviceRole.isIPad {
            return false
        }

        switch mode {
        case .free:
            return true
        case .route:
            return selectedRoute != nil
        case .structured:
            return basicGoalSelected ||
                advancedWorkout != nil || selectedWorkout != nil
        }
    }

    private func submitQuickRun(
        captureDevice:
            WorkoutCaptureDevice
    ) {
        guard !launchInProgress else { return }
        guard canSubmitQuickRun(
            captureDevice:
                captureDevice
        ) else {
            return
        }

        let friends = social.resolvedQuickTrainPartners(selectedFriendIDs)

        var routeAlerts =
            routeGuardianDraft
                .configuration
        if !isAdvancedSetup {
            routeAlerts.enabled = false
        }

        launchFailure = nil
        // The environment chosen in Workout Details is authoritative.
        // A previously selected structured workout must not override it.
        let runEnvironment = environment
        let launchAdvancedWorkout: PlannedSession? =
            basicGoalSelected ? basicGoalWorkout : advancedWorkout
        let basicGhostTarget: TimeInterval? = basicGhostSelected &&
            mode == .route && guidanceRoute != nil && environment == .outdoor
            ? TimeInterval(basicGhostTargetMinutes * 60) : nil
        var configuration = RunQuickStartConfiguration(
                mode: mode,
                route:
                    mode == .route
                        ? selectedRoute
                        : nil,
                workout:
                    mode == .structured
                        ? selectedWorkout
                        : nil,
                captureDevice:
                    captureDevice,
                environment: runEnvironment,
                treadmillInclinePercent:
                    runEnvironment == .treadmill
                        ? launchAdvancedWorkout?.resolvedWorkoutBlocks
                            .first(where: { $0.kind == .run })?
                            .treadmillInclinePercent ?? 0
                        : nil,
                audioCoach:
                    audioCoachDraft.enabled
                        ? audioCoachConfiguration
                        : .disabled,
                routeAlerts:
                    routeAlerts,
                ghostTargetDurationSeconds:
                    basicGhostTarget ?? (
                        isAdvancedSetup && ghostDraft.enabled &&
                        guidanceRoute != nil ? ghostDraft.targetDuration : nil
                    ),
                ghostUpdates:
                    basicGhostTarget != nil
                        ? settings.ghostRaceAudioConfiguration
                        : (isAdvancedSetup && guidanceRoute != nil &&
                           ghostDraft.enabled && ghostDraft.targetDuration != nil
                            ? ghostDraft.resolvedUpdates(
                                fallback: settings.ghostRaceAudioConfiguration
                              ) : nil),
                autoPauseEnabled:
                    runEnvironment == .outdoor &&
                    (
                        isAdvancedSetup
                            ? autoPausePreference
                            : .appDefault
                    )
                    .resolved(
                        appDefault:
                            settings.autoPauseOutdoorWorkouts
                    ),
                spotifyPlaylist:
                    isAdvancedSetup &&
                    spotifyAutoplay
                        ? selectedSpotifyPlaylist
                        : nil,
                spotifyAutoplay:
                    isAdvancedSetup &&
                    spotifyAutoplay &&
                    selectedSpotifyPlaylist != nil,
                friends: friends,
                socialMode:
                    socialMode,
                gearIDs: selectedGearIDs,
                watchStartMode: watchStartMode,
                customWorkoutTitle: mode == .structured &&
                    advancedWorkout != nil ? nil : quickWorkoutName
            )
        configuration.petIDs = selectedPetIDs
        configuration.advancedWorkout = mode == .structured
            ? launchAdvancedWorkout.map {
                ATHLTHQuickRunTimelineAdapter.withEnvironment(
                    $0, environment: runEnvironment
                )
            } : nil
        configuration.routeWarmup = mode == .route ? routeWarmup : .disabled
        configuration.ghostPacingStrategy = ghostDraft.pacingStrategy
        launchInProgress = true
        Task { @MainActor in
            let failure = await onStart(configuration)
            launchInProgress = false
            if let failure {
                launchFailure = failure
            } else {
                dismiss()
            }
        }
    }

    private var quickRunGuidanceCard:
        some View {
        ATHLTHPlanSurface(density: .compact) {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                NavigationLink {
                    RunGuidanceSetupView(
                        audioCoach:
                            $audioCoachDraft,
                        routeGuardian:
                            $routeGuardianDraft,
                        ghost:
                            $ghostDraft,
                        route:
                            guidanceRoute,
                        structuredWorkout:
                            mode == .structured
                                ? selectedWorkout
                                : nil
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(
                            systemName:
                                "waveform.and.mic"
                        )
                        .font(
                            .system(
                                size: 18,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .premiumGold
                        )
                        .frame(
                            width: 44,
                            height: 44
                        )
                        .background(
                            ATHLTHTheme
                                .premiumGoldSoft,
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Run tools",
                                    norwegian:
                                        "Løpsverktøy"
                                )
                            )
                            .font(.headline)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Audio Coach, Ghost and route tools for this run",
                                    norwegian:
                                        "Audio Coach, Ghost og ruteverktøy for denne økten"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                            .multilineTextAlignment(
                                .leading
                            )
                        }

                        Spacer()

                        Image(
                            systemName:
                                "chevron.right"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(
                            .secondary
                        )
                    }
                    .contentShape(
                        Rectangle()
                    )
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    runGuidanceFeaturePill(
                        title:
                            "Audio Coach",
                        icon:
                            "waveform.and.person.filled",
                        active:
                            audioCoachDraft.enabled,
                        unavailable: false
                    ) {
                        activateAdvancedGuidanceIfNeeded()

                        withAnimation(
                            .easeInOut(
                                duration: 0.16
                            )
                        ) {
                            audioCoachDraft.enabled
                                .toggle()
                        }
                    }

                    runGuidanceFeaturePill(
                        title: "Ghost",
                        icon:
                            "figure.run.circle.fill",
                        active:
                            ghostDraft.enabled &&
                            guidanceRoute != nil,
                        unavailable:
                            guidanceRoute == nil
                    ) {
                        guard guidanceRoute != nil
                        else {
                            return
                        }

                        activateAdvancedGuidanceIfNeeded()

                        withAnimation(
                            .easeInOut(
                                duration: 0.16
                            )
                        ) {
                            ghostDraft.enabled
                                .toggle()
                        }
                    }

                    runGuidanceFeaturePill(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Route",
                                norwegian:
                                    "Rute"
                            ),
                        icon:
                            "location.fill",
                        active:
                            routeGuardianDraft
                                .enabled &&
                            guidanceRoute != nil,
                        unavailable:
                            guidanceRoute == nil
                    ) {
                        guard guidanceRoute != nil
                        else {
                            return
                        }

                        activateAdvancedGuidanceIfNeeded()

                        withAnimation(
                            .easeInOut(
                                duration: 0.16
                            )
                        ) {
                            routeGuardianDraft
                                .enabled
                                .toggle()
                        }
                    }
                }

                Text(
                    guidanceRoute == nil
                        ? ATHLTHLocalization.choose(
                            english:
                                "Tap a tool to turn it on or off. Choose a route to unlock Ghost and Route.",
                            norwegian:
                                "Trykk på et verktøy for å skru det av eller på. Velg en rute for å bruke Ghost og Rute."
                        )
                        : guidanceSummary
                )
                .font(
                    .system(
                        size: 11,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }
        }
    }

    private func runGuidanceFeaturePill(
        title: String,
        icon: String,
        active: Bool,
        unavailable: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(
                    systemName: icon
                )
                .font(
                    .system(
                        size: 10,
                        weight: .semibold
                    )
                )

                Text(title)
                    .font(
                        .system(
                            size: 10,
                            weight: .semibold
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(
                        0.72
                    )

                Spacer(
                    minLength: 1
                )

                Image(
                    systemName:
                        active
                            ? "checkmark.circle.fill"
                            : "circle"
                )
                .font(
                    .system(
                        size: 9,
                        weight: .semibold
                    )
                )
            }
            .foregroundStyle(
                unavailable
                    ? ATHLTHTheme
                        .mutedText
                        .opacity(0.52)
                    : (
                        active
                            ? ATHLTHTheme
                                .vitality
                            : ATHLTHTheme
                                .primaryText
                    )
            )
            .padding(
                .horizontal,
                9
            )
            .frame(
                maxWidth: .infinity
            )
            .frame(height: 36)
            .background(
                (
                    active
                        ? ATHLTHTheme
                            .vitalitySoft
                        : Color.primary
                            .opacity(0.04)
                ),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        active
                            ? ATHLTHTheme
                                .vitality
                                .opacity(0.13)
                            : Color.primary
                                .opacity(0.025),
                        lineWidth: 0.7
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(unavailable)
        .opacity(
            unavailable
                ? 0.62
                : 1
        )
        .accessibilityValue(
            unavailable
                ? ATHLTHLocalization.choose(
                    english:
                        "Unavailable without a route",
                    norwegian:
                        "Krever en rute"
                )
                : (
                    active
                        ? ATHLTHLocalization.choose(
                            english: "On",
                            norwegian: "På"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Off",
                            norwegian: "Av"
                        )
                )
        )
    }

    private func activateAdvancedGuidanceIfNeeded() {
        guard !isAdvancedSetup
        else {
            return
        }

        isAdvancedSetup = true
        settings.recordAdvancedSetup(
            true,
            for: .running
        )
    }

    private func selectedRouteVisibilityIcon(
        _ visibility: ProfileVisibility
    ) -> String {
        switch visibility {
        case .privateOnly:
            return "lock.fill"
        case .friends:
            return "person.2.fill"
        case .publicProfile:
            return "globe.europe.africa.fill"
        }
    }

    private func selectedRouteVisibilityTint(
        _ visibility: ProfileVisibility
    ) -> Color {
        switch visibility {
        case .privateOnly:
            return ATHLTHTheme.accentDeep
        case .friends:
            return ATHLTHTheme.recoveryBlue
        case .publicProfile:
            return ATHLTHTheme.vitality
        }
    }

    private var guidanceRoute:
        TrainingRoute?
    {
        guard environment == .outdoor else {
            return nil
        }

        if mode == .route {
            return selectedRoute
        }

        guard mode == .structured,
              let routeID =
                advancedWorkout?.routeID ?? selectedWorkout?.routeID
        else {
            return nil
        }

        return session.savedRoutes.first {
            $0.id == routeID
        }
    }

    private var guidanceSummary: String {
        var parts: [String] = []

        if audioCoachDraft.enabled {
            parts.append("Audio Coach")
        }

        if routeGuardianDraft.enabled,
           guidanceRoute != nil {
            parts.append(ATHLTHLocalization.choose(english: "Navigation", norwegian: "Navigasjon"))
        }

        if ghostDraft.enabled,
           guidanceRoute != nil {
            parts.append("Ghost Race")
        }

        return parts.isEmpty
            ? "Tap to configure this workout"
            : parts.joined(
                separator: " · "
            )
    }

    private var audioCoachConfiguration:
        WatchAudioCoachConfiguration {
        guard session.canAccess(.audioCoach)
        else {
            return .disabled
        }

        let routeDistanceMeters =
            guidanceRoute.map {
                $0.distanceKilometers *
                    1_000
            }

        return audioCoachDraft.configuration(
            routeDistanceMeters: routeDistanceMeters,
            maximumHeartRateBPM:
                session.onboardingProfile?.maximumHeartRateBPM.map(Double.init)
        )
    }

    private var distanceToSelectedRouteStart:
        CLLocationDistance?
    {
        guard let route = selectedRoute,
              let first =
                route.coordinates
                    .min(
                        by: {
                            $0.sequence <
                                $1.sequence
                        }
                    ),
              let location =
                routeLocationProbe.location
        else {
            return nil
        }

        let start =
            CLLocation(
                latitude: first.latitude,
                longitude: first.longitude
            )

        return location.distance(from: start)
    }

    private func routeStartDistanceText(
        _ meters: CLLocationDistance
    ) -> String {
        if meters >= 1_000 {
            return String(
                format:
                    "%.1f km from route start",
                meters / 1_000
            )
        }

        return "\(Int(meters.rounded())) m from route start"
    }

    private func openDirectionsToRouteStart() {
        guard let route = selectedRoute,
              let first =
                route.coordinates
                    .min(
                        by: {
                            $0.sequence <
                                $1.sequence
                        }
                    )
        else {
            return
        }

        let item =
            MKMapItem(
                placemark:
                    MKPlacemark(
                        coordinate:
                            CLLocationCoordinate2D(
                                latitude:
                                    first.latitude,
                                longitude:
                                    first.longitude
                            )
                    )
            )
        item.name =
            route.title + " · Start"

        item.openInMaps(
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey:
                    MKLaunchOptionsDirectionsModeWalking
            ]
        )
    }

}

struct WalkQuickStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var pets: ATHLTHPetStore
    @EnvironmentObject private var spotify: SpotifyPlaybackStore

    let trainingDeviceProvider: TrainingDeviceProvider
    let watchConnected: Bool
    var plannedSession: PlannedSession? = nil
    let onStart: (WalkQuickStartConfiguration) async -> String?
    @State private var launchInProgress = false
    @State private var launchFailure: String?

    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var socialMode:
        SocialWorkoutParticipationMode =
            .physical
    @State private var selectedGearIDs: Set<UUID> = []
    @State private var selectedPetIDs: Set<UUID> = []
    @State private var audioCoachDraft = AudioCoachDraft()
    @State private var didLoadAudioCoachDefaults = false
    @State private var isAdvancedSetup = false
    @State private var showingWalkDetails = false
    @State private var autoPausePreference:
        WorkoutAutoPausePreference = .appDefault
    @State private var selectedSpotifyPlaylist:
        SpotifyPlaylistReference?
    @State private var spotifyAutoplay = false
    @State private var showingSpotifyPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text(ATHLTHLocalization.choose(
                            english: "Walking", norwegian: "Gåing"
                        ))
                        .font(.system(size: 26, weight: .medium, design: .serif))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        Spacer()
                        Button {
                            isAdvancedSetup.toggle()
                            if isAdvancedSetup { showingWalkDetails = true }
                        } label: {
                            Text(isAdvancedSetup
                                ? ATHLTHLocalization.choose(
                                    english: "Advanced", norwegian: "Avansert"
                                  )
                                : "Basic")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTrainDesign.bronze)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 40)
                                .background(.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    ATHLTHBasicActivityHero(
                        title: ATHLTHLocalization.choose(
                            english: "Free walking", norwegian: "Fri gåtur"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Start a walk without planning. Add coaching or company if you want.",
                            norwegian: "Start en gåtur uten plan. Legg til veiledning eller selskap hvis du ønsker."
                        ),
                        symbol: "figure.walk",
                        isSelected: true,
                        actionTitle: ATHLTHLocalization.choose(
                            english: "Start free walk", norwegian: "Start fri gåtur"
                        )
                    ) {
                        startWalk(using:
                            trainingDeviceProvider == .appleWatch &&
                            watchConnected && !ATHLTHDeviceRole.isIPad
                                ? .appleWatch : .iPhone
                        )
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "Make your walk yours",
                        norwegian: "Tilpass gåturen"
                    ))
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHTrainDesign.ink)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 10) {
                        if session.canAccess(.audioCoach) {
                            ATHLTHBasicActivityModeTile(
                            title: "Audio Coach",
                            subtitle: ATHLTHLocalization.choose(
                                english: "Spoken guidance", norwegian: "Lydveiledning"
                            ),
                            symbol: "waveform",
                            selected: audioCoachDraft.enabled
                        ) {
                            guard session.canAccess(.audioCoach) else { return }
                            audioCoachDraft.enabled.toggle()
                            }
                        }
                        ATHLTHBasicActivityModeTile(
                            title: ATHLTHLocalization.choose(
                                english: "Workout details", norwegian: "Øktdetaljer"
                            ),
                            subtitle: ATHLTHLocalization.choose(
                                english: "Gear, pets and friends",
                                norwegian: "Utstyr, kjæledyr og venner"
                            ),
                            symbol: "slider.horizontal.3",
                            selected: showingWalkDetails
                        ) {
                            showingWalkDetails.toggle()
                        }
                    }

                    if let plannedSession {
                        PlannedQuickStartContextCard(workout: plannedSession)
                    }

                    if showingWalkDetails || isAdvancedSetup {
                        WorkoutGearSelectionCard(
                        selectedGearIDs: $selectedGearIDs,
                        activity: .walking
                    )
                    ATHLTHQuickWorkoutPetPicker(selectedPetIDs: $selectedPetIDs)

                    ATHLTHPlanSurface(density: .compact) {
                        VStack(
                            alignment: .leading,
                            spacing: 14
                        ) {
                            WorkoutFriendPicker(
                                selectedFriendIDs:
                                    $selectedFriendIDs
                            )

                            if !selectedFriendIDs
                                .isEmpty {
                                Divider()

                                WorkoutSocialModePicker(
                                    mode:
                                        $socialMode
                                )
                            }
                        }
                    }

                    }

                    if isAdvancedSetup {
                        QuickStartAutoPauseCard(
                            preference: $autoPausePreference,
                            appDefaultEnabled:
                                settings.autoPauseOutdoorWorkouts
                        )

                        QuickStartSpotifyCard(
                            playlist:
                                $selectedSpotifyPlaylist,
                            autoplay:
                                $spotifyAutoplay
                        ) {
                            showingSpotifyPicker = true
                        }

                        NavigationLink {
                            PerWorkoutAudioCoachView(
                                draft:
                                    $audioCoachDraft,
                                showRouteOptions: false,
                                showStructuredOptions: false
                            )
                        } label: {
                            ATHLTHPlanSurface(density: .compact) {
                                HStack(spacing: 12) {
                                    Image(
                                        systemName:
                                            "waveform.and.mic"
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .premiumGold
                                    )
                                    .frame(
                                        width: 40,
                                        height: 40
                                    )
                                    .background(
                                        ATHLTHTheme
                                            .premiumGoldSoft,
                                        in:
                                            RoundedRectangle(
                                                cornerRadius:
                                                    12
                                            )
                                    )

                                    VStack(
                                        alignment: .leading,
                                        spacing: 3
                                    ) {
                                        Text(
                                            "Guidance & Alerts"
                                        )
                                        .font(
                                            .subheadline
                                                .weight(
                                                    .semibold
                                                )
                                        )

                                        Text(
                                            audioCoachDraft
                                                .enabled
                                                ? "Audio Coach · tap to adjust"
                                                : "Tap to configure this walk"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                    }

                                    Spacer()

                                    Image(
                                        systemName:
                                            "chevron.right"
                                    )
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                }
                .padding()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    if let launchFailure {
                        ATHLTHQuickWatchLaunchNotice(message: launchFailure) {
                            self.launchFailure = nil
                        }
                        .padding(.horizontal, 15)
                    }
                    if launchInProgress {
                        ProgressView(ATHLTHLocalization.choose(
                            english: "Starting workout…",
                            norwegian: "Starter treningsøkten…"
                        ))
                        .font(.caption)
                        .padding(.horizontal, 18)
                    }
                    ATHLTHQuickStartDeviceLaunchBar(
                    watchAvailable: watchConnected || ATHLTHDeviceRole.isIPad,
                    onIPhone: { startWalk(using: .iPhone) },
                    onAppleWatch: { startWalk(using: .appleWatch) },
                    preferAppleWatch: watchConnected && !ATHLTHDeviceRole.isIPad,
                    supportingText: ATHLTHDeviceRole.isIPad
                        ? ATHLTHLocalization.choose(
                            english: "Sent via your signed-in iPhone.",
                            norwegian: "Sendes via innlogget iPhone."
                        )
                        : nil
                )
                    .allowsHitTesting(!launchInProgress)
                    .opacity(launchInProgress ? 0.65 : 1)
                }
            }
            .navigationTitle("Start Walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingSpotifyPicker) {
                SpotifyPlaylistPickerView(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Walk Playlist",
                            norwegian: "Spilleliste for gåtur"
                        ),
                    selection:
                        $selectedSpotifyPlaylist
                )
                .onDisappear {
                    spotifyAutoplay =
                        selectedSpotifyPlaylist != nil
                }
            }
            .task {
                if let invited = social.takePreparedQuickTrainFriends() {
                    selectedFriendIDs = invited
                }

                if !didLoadAudioCoachDefaults {
                    audioCoachDraft.load(from: settings)
                    // Plan/individual workout choices supersede global defaults.
                    // Never write these session-scoped overrides back to Settings.
                    if let savedCoach = plannedSession?.audioCoachConfiguration {
                        audioCoachDraft.load(configuration: savedCoach)
                    }
                    didLoadAudioCoachDefaults = true
                }

                // Use only the explicit Settings default for a
                // fresh quick walk; never inherit the previous workout's
                // temporary playlist selection.
                selectedSpotifyPlaylist =
                    settings.spotifyDefaultPlaylist
                spotifyAutoplay =
                    settings.spotifyAutoplayLinkedPlaylists &&
                    selectedSpotifyPlaylist != nil

                if spotify.isConnected &&
                    spotify.playlists.isEmpty {
                    await spotify.refreshPlaylists()
                }

                if social.trainingPartners.isEmpty {
                    await social.refresh()
                }

                if gear.items.isEmpty {
                    await gear.refresh()
                }
            }
        }
    }

    private func startWalk(using device: WorkoutCaptureDevice) {
        guard !launchInProgress else { return }
        guard device == .iPhone ||
            watchConnected || ATHLTHDeviceRole.isIPad else { return }
        let friends = social.resolvedQuickTrainPartners(selectedFriendIDs)

        launchFailure = nil
        var configuration = WalkQuickStartConfiguration(
                captureDevice: device,
                audioCoach:
                    session.canAccess(.audioCoach) && audioCoachDraft.enabled
                        ? audioCoachDraft.configuration()
                        : .disabled,
                autoPauseEnabled:
                    (
                        isAdvancedSetup
                            ? autoPausePreference
                            : .appDefault
                    )
                    .resolved(
                        appDefault:
                            settings.autoPauseOutdoorWorkouts
                    ),
                spotifyPlaylist:
                    isAdvancedSetup &&
                    spotifyAutoplay
                        ? selectedSpotifyPlaylist
                        : nil,
                spotifyAutoplay:
                    isAdvancedSetup &&
                    spotifyAutoplay &&
                    selectedSpotifyPlaylist != nil,
                friends:
                    friends,
                socialMode:
                    socialMode,
                gearIDs: selectedGearIDs
            )
        configuration.petIDs = selectedPetIDs
        launchInProgress = true
        Task { @MainActor in
            let failure = await onStart(configuration)
            launchInProgress = false
            if let failure {
                launchFailure = failure
            } else {
                dismiss()
            }
        }
    }
}

// A recoverable Watch error stays with the quick-start card and draft.
private struct ATHLTHQuickWatchLaunchNotice: View {
    let message: String
    let onDismiss: () -> Void

    private var compactMessage: String {
        let normalized = message.lowercased()
        if normalized.contains("locked") || normalized.contains("unlock")
            || normalized.contains("låst") || normalized.contains("lås opp") {
            return ATHLTHLocalization.choose(
                english: "Unlock Apple Watch and try again.",
                norwegian: "Lås opp Apple Watch og prøv igjen."
            )
        }
        return message
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.circle")
                .accessibilityHidden(true)
            Text(compactMessage)
                .lineLimit(1)
                .minimumScaleFactor(0.83)
                .accessibilityLabel(message)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Dismiss message", norwegian: "Lukk meldingen"
            ))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(ATHLTHTrainDesign.bronze)
        .frame(height: 27)
    }
}

struct StrengthQuickStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore

    let onChoose: (PlannedSession) -> Void
    @State private var draftID = UUID()

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    private let modes: [WorkoutBlockGroupKind] = [
        .superset, .circuit, .emom, .amrap, .dropSet
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(ATHLTHLocalization.choose(
                        english: "Strength", norwegian: "Styrketrening"
                    ))
                    .font(.system(size: 26, weight: .medium, design: .serif))
                    .foregroundStyle(ATHLTHTrainDesign.ink)

                    ATHLTHBasicActivityHero(
                        title: ATHLTHLocalization.choose(
                            english: "Free strength training",
                            norwegian: "Fri styrketrening"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Start without a plan. Add exercises and sets as you go.",
                            norwegian: "Start uten plan. Legg til øvelser og sett underveis."
                        ),
                        symbol: "dumbbell",
                        isSelected: false,
                        actionTitle: ATHLTHLocalization.choose(
                            english: "Start free strength",
                            norwegian: "Start fri styrketrening"
                        )
                    ) {
                        beginWorkout(emptySession)
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "Other ways to train",
                        norwegian: "Andre måter å trene styrke på"
                    ))
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHTrainDesign.ink)

                    LazyVGrid(columns: columns, spacing: 10) {
                        NavigationLink {
                            StrengthQuickBuilderView { workout in
                                beginWorkout(workout)
                            }
                        } label: {
                            ATHLTHBasicActivityModeTile(
                                title: ATHLTHLocalization.choose(
                                    english: "Training workout",
                                    norwegian: "Treningsøkt"
                                ),
                                subtitle: ATHLTHLocalization.choose(
                                    english: "Choose exercises and sets",
                                    norwegian: "Velg øvelser og sett"
                                ),
                                symbol: "list.bullet.clipboard",
                                selected: false,
                                asNavigationLabel: true
                            ) {}
                        }
                        .buttonStyle(.plain)

                        ForEach(modes, id: \.self) { kind in
                            NavigationLink {
                                strengthModeBuilder(kind)
                            } label: {
                                ATHLTHBasicActivityModeTile(
                                    title: kind.title,
                                    subtitle: modeSubtitle(kind),
                                    symbol: kind.symbol,
                                    selected: false,
                                asNavigationLabel: true
                                ) {}
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    NavigationLink {
                        strengthAdvancedBuilder
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Advanced workout builder",
                            norwegian: "Avansert øktbygger"
                        ), systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("athlth-strength-advanced-builder")
                }
                .padding(16)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Strength", norwegian: "Styrke"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) { dismiss() }
                }
            }
        }
    }

    private func modeSubtitle(_ mode: WorkoutBlockGroupKind) -> String {
        switch mode {
        case .superset: return ATHLTHLocalization.choose(
            english: "Exercises back to back", norwegian: "Øvelser etter hverandre"
        )
        case .circuit: return ATHLTHLocalization.choose(
            english: "Stations and rounds", norwegian: "Stasjoner og runder"
        )
        case .emom: return ATHLTHLocalization.choose(
            english: "Every minute", norwegian: "Hvert minutt"
        )
        case .amrap: return ATHLTHLocalization.choose(
            english: "As many rounds as possible", norwegian: "Flest mulig runder"
        )
        case .dropSet: return ATHLTHLocalization.choose(
            english: "Reduce the load", norwegian: "Reduser vekten"
        )
        case .intervals: return ATHLTHLocalization.choose(
            english: "Intervals", norwegian: "Intervaller"
        )
        }
    }

    private func strengthModeBuilder(_ kind: WorkoutBlockGroupKind) -> some View {
        WorkoutTemplateBuilderView(
            initialTitle: kind.title,
            initialQuickAdd: kind.rawValue,
            draftContext: "quick-strength-\(draftID.uuidString)-\(kind.rawValue)",
            initialActivity: .strength,
            initialStudioAdvanced: true,
            onAddStandalone: { workout in
                beginWorkout(workout)
                return true
            },
            saveButtonTitle: ATHLTHLocalization.choose(
                english: "Continue to start", norwegian: "Gå videre til start"
            )
        )
    }

    private var strengthAdvancedBuilder: some View {
        WorkoutTemplateBuilderView(
            initialTitle: ATHLTHLocalization.choose(
                english: "Strength workout", norwegian: "Styrkeøkt"
            ),
            draftContext: "quick-strength-advanced-\(draftID.uuidString)",
            initialActivity: .strength,
            initialStudioAdvanced: true,
            onAddStandalone: { workout in
                beginWorkout(workout)
                return true
            },
            saveButtonTitle: ATHLTHLocalization.choose(
                english: "Continue to start", norwegian: "Gå videre til start"
            )
        )
    }

    private func beginWorkout(_ workout: PlannedSession) {
        social.prepareQuickTrainFriendsForLaunch()
        onChoose(workout)
        dismiss()
    }

    private var emptySession: PlannedSession {
        PlannedSession(
            id: UUID(),
            title: ATHLTHLocalization.choose(
                english: "Free strength training", norwegian: "Fri styrketrening"
            ),
            kind: .strength, scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [],
            notes: "Open strength session · exercises can be added during training",
            runningWorkout: nil
        )
    }
}

struct StrengthQuickBuilderView: View {
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore

    let onStart: (PlannedSession) -> Void

    @State private var title = "Strength Workout"
    @State private var exercises: [PlannedExercise] = []
    @State private var showingExerciseLibrary = false
    @State private var exerciseBeingEdited: PlannedExercise?
    @State private var pendingTreadmillSetup: PlannedExercise?

    var body: some View {
        Form {
            Section("Workout") {
                TextField("Workout name", text: $title)

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Add the exercises you want to complete. Once training starts, ATHLTH keeps you focused on one exercise at a time.",
                        norwegian:
                            "Legg inn øvelsene du skal gjennomføre. Når økten starter holder ATHLTH fokuset på én øvelse om gangen."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Exercises") {
                if exercises.isEmpty {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Add at least one exercise before continuing, or go back and choose Train without a plan.",
                            norwegian:
                                "Legg til minst én øvelse før du fortsetter, eller gå tilbake og velg Tren uten plan."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                ForEach(Array(exercises.enumerated()), id: \.element.id) {
                    index,
                    exercise in

                    Button {
                        exerciseBeingEdited = exercise
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(width: 28, height: 28)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: Circle()
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.embeddedExercise.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                if exercise.isWarmUpExercise {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "WARM-UP",
                                            norwegian: "OPPVARMING"
                                        ),
                                        systemImage: "flame.fill"
                                    )
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(ATHLTHTheme.premiumGold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(ATHLTHTheme.premiumGoldSoft, in: Capsule())
                                }

                                Text(exerciseSummary(exercise))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            if let position = exercises.firstIndex(where: { $0.id == exercise.id }) {
                                exercises[position].setEntireExerciseWarmUp(
                                    !exercises[position].isWarmUpExercise
                                )
                            }
                        } label: {
                            Label(
                                exercise.isWarmUpExercise
                                    ? ATHLTHLocalization.choose(
                                        english: "Mark as working sets",
                                        norwegian: "Marker som arbeidssett"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Mark as warm-up",
                                        norwegian: "Marker som oppvarming"
                                    ),
                                systemImage: exercise.isWarmUpExercise ? "dumbbell.fill" : "flame.fill"
                            )
                        }
                    }
                }
                .onDelete { offsets in
                    exercises.remove(atOffsets: offsets)
                }
                .onMove { offsets, destination in
                    exercises.move(
                        fromOffsets: offsets,
                        toOffset: destination
                    )
                }

                Button {
                    showingExerciseLibrary = true
                } label: {
                    Label(
                        "Add Exercise",
                        systemImage: "plus.circle.fill"
                    )
                }
            }

            Section {
                Button {
                    onStart(builtSession)
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Continue to Start",
                            norwegian:
                                "Fortsett til Start"
                        ),
                        systemImage: "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .disabled(
                    title.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty ||
                    exercises.isEmpty
                )
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Build Workout")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExerciseLibrary) {
            NavigationStack {
                ExerciseLibraryView(
                    selectionTitle: ATHLTHLocalization.choose(
                        english: "Add to Workout",
                        norwegian: "Legg til i økten"
                    ),
                    selectedExerciseCounts: Dictionary(
                        exercises.compactMap(\.exerciseID).map { ($0, 1) },
                        uniquingKeysWith: +
                    )
                ) { entry in
                    addExercise(entry.exercise)
                }
            }
        }
        .sheet(item: $pendingTreadmillSetup) { exercise in
            PlannedExerciseEditorView(
                exercise: exercise,
                advancedMode: false
            ) { updated in
                exercises.append(updated)
                pendingTreadmillSetup = nil
            }
        }
        .sheet(item: $exerciseBeingEdited) { exercise in
            PlannedExerciseEditorView(
                exercise: exercise,
                advancedMode: false
            ) { updated in
                if let index = exercises.firstIndex(
                    where: { $0.id == updated.id }
                ) {
                    exercises[index] = updated
                }
                exerciseBeingEdited = nil
            }
        }
        .task {
            await exerciseLibrary.refresh()
        }
    }

    private var builtSession: PlannedSession {
        PlannedSession(
            id: UUID(),
            title:
                title.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            kind: .strength,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: exercises,
            notes: "Built immediately before training",
            runningWorkout: nil
        )
    }

    private func addExercise(_ exercise: Exercise) {
        let draft = StrengthTreadmillWarmUpDefaults.plannedExercise(
            for: exercise
        )
        if StrengthTreadmillWarmUpDefaults.isTreadmill(exercise.snapshot.name) ||
            StrengthTreadmillWarmUpDefaults.isTreadmill(exercise.snapshot.displayName) {
            pendingTreadmillSetup = draft
        } else {
            exercises.append(draft)
        }
    }

    private func exerciseSummary(
        _ exercise: PlannedExercise
    ) -> String {
        var parts = [
            exercise.compactTargetSummary
        ]

        if let load =
                exercise.compactLoadSummary {
            parts.append(load)
        }

        if let rpe = exercise.targetRPE {
            parts.append(
                String(format: "RPE %.1f", rpe)
            )
        }

        if let rest = exercise.restSeconds {
            parts.append("\(rest)s rest")
        }

        return parts.joined(separator: " · ")
    }
}

/// A compatibility entry point for Quick Train and Run Tools.
struct AudioCoachSetupCard: View {
    @Binding var draft: AudioCoachDraft
    let showRouteOptions: Bool
    let showStructuredOptions: Bool

    var body: some View {
        ATHLTHAudioCoachSessionStudio(
            draft: $draft,
            showRouteOptions: showRouteOptions,
            showStructuredOptions: showStructuredOptions
        )
    }
}

func watchRunningWorkoutTransfer(
    from workout: RunningWorkoutTemplate
) -> WatchRunningWorkoutTransfer {
    var steps: [WatchRunningWorkoutStep] = []

    for block in workout.blocks {
        let repetitions = max(block.repetitions, 1)

        for repetition in 0..<repetitions {
            steps.append(
                watchRunningStep(
                    title: block.title,
                    target: block.work
                )
            )

            if repetition < repetitions - 1,
               let recovery = block.recovery {
                steps.append(
                    watchRunningStep(
                        title: "Recovery",
                        target: recovery
                    )
                )
            }
        }
    }

    return WatchRunningWorkoutTransfer(
        title: workout.title,
        steps: steps
    )
}

private func watchRunningStep(
    title: String,
    target: RunningStepTarget
) -> WatchRunningWorkoutStep {
    let measure: WatchRunningStepMeasure

    switch target.measure {
    case .distance:
        measure = .distance
    case .time:
        measure = .time
    case .open:
        measure = .open
    }

    return WatchRunningWorkoutStep(
        id: UUID(),
        title: title,
        measure: measure,
        distanceMeters: target.distanceMeters,
        durationSeconds: target.durationSeconds,
        intensityText: watchIntensityText(
            target.intensity
        ),
        targetPaceMinSecondsPerKilometer:
            target.intensity
                .paceMinSecondsPerKilometer,
        targetPaceMaxSecondsPerKilometer:
            target.intensity
                .paceMaxSecondsPerKilometer
    )
}

private func watchIntensityText(
    _ intensity: RunningIntensityTarget
) -> String? {
    switch intensity.kind {
    case .none:
        return nil
    case .easy:
        return "Easy effort"
    case .heartRateZone:
        return intensity.heartRateZone.map {
            "Heart-rate zone \($0)"
        }
    case .rpe:
        return intensity.rpe.map {
            String(format: "RPE %.1f", $0)
        }
    case .pace:
        let low = intensity.paceMinSecondsPerKilometer
        let high = intensity.paceMaxSecondsPerKilometer

        if let low, let high {
            return "\(paceText(low))–\(paceText(high)) /km"
        }

        return (low ?? high).map {
            "\(paceText($0)) /km"
        }
    }
}

private func paceText(
    _ seconds: TimeInterval
) -> String {
    let total = max(Int(seconds.rounded()), 0)
    return String(
        format: "%d:%02d",
        total / 60,
        total % 60
    )
}

private extension Optional where Wrapped == String {
    var orEmpty: String {
        self ?? ""
    }
}


 // Shared compact, accessible pet picker for both Quick Run and Quick Walk.
 // Avoid the floating single-choice menu: athletes may bring more than one pet.
 private struct ATHLTHQuickWorkoutPetPicker: View {
     @EnvironmentObject private var pets: ATHLTHPetStore
     @Binding var selectedPetIDs: Set<UUID>
     @State private var expanded = false

     var body: some View {
         if !pets.visiblePets.isEmpty {
             ATHLTHPlanSurface(ghost: false, density: .compact) {
                 DisclosureGroup(isExpanded: $expanded) {
                     VStack(alignment: .leading, spacing: 10) {
                         ForEach(pets.visiblePets) { pet in
                             Button {
                                 if selectedPetIDs.contains(pet.id) {
                                     selectedPetIDs.remove(pet.id)
                                 } else {
                                     selectedPetIDs.insert(pet.id)
                                 }
                             } label: {
                                 HStack(spacing: 11) {
                                     ATHLTHPetAvatar(pet: pet, size: 38)
                                     VStack(alignment: .leading, spacing: 2) {
                                         Text(pet.name)
                                             .font(.subheadline.weight(.semibold))
                                             .foregroundStyle(ATHLTHPlanDesign.ink)
                                         Text(pet.breed ?? pet.speciesName)
                                             .font(.caption)
                                             .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                     }
                                     Spacer()
                                     Image(systemName: selectedPetIDs.contains(pet.id)
                                         ? "checkmark.circle.fill" : "circle")
                                         .font(.title3)
                                         .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                 }
                                 .frame(minHeight: 48)
                                 .contentShape(Rectangle())
                             }
                             .buttonStyle(.plain)
                             .accessibilityAddTraits(
                                 selectedPetIDs.contains(pet.id) ? .isSelected : []
                             )
                         }
                         Text(ATHLTHLocalization.choose(
                             english: "You can select several companions for this workout.",
                             norwegian: "Du kan velge flere turkamerater til denne økten."
                         ))
                         .font(.caption)
                         .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                     }
                     .padding(.top, 12)
                 } label: {
                     HStack(spacing: 11) {
                         Image(systemName: "pawprint.fill")
                             .font(.system(size: 17, weight: .medium))
                             .foregroundStyle(ATHLTHPlanDesign.accentInk)
                             .frame(width: 36, height: 36)
                             .background(ATHLTHPlanDesign.selectedSurface,
                                         in: RoundedRectangle(cornerRadius: 11))
                         VStack(alignment: .leading, spacing: 3) {
                             Text(ATHLTHLocalization.choose(
                                 english: "Training companions", norwegian: "Turkamerat"
                             ))
                             .font(.subheadline.weight(.semibold))
                             .foregroundStyle(ATHLTHPlanDesign.ink)
                             Text(pets.visiblePets.filter {
                                 selectedPetIDs.contains($0.id)
                             }.map(\.name).joined(separator: ", ").isEmpty
                                 ? ATHLTHLocalization.choose(
                                     english: "Optional · choose a pet",
                                     norwegian: "Valgfritt · velg turkamerat")
                                 : pets.visiblePets.filter {
                                     selectedPetIDs.contains($0.id)
                                 }.map(\.name).joined(separator: ", "))
                                 .font(.caption)
                                 .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                         }
                     }
                     .frame(minHeight: 48)
                 }
                 .tint(ATHLTHPlanDesign.accentInk)
             }
         }
     }
 }
