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
    var enabled = false
    var distanceTriggerEnabled = true
    var timeTriggerEnabled = false
    var distanceIntervalKilometers = 1.0
    var timeIntervalMinutes = 10

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
        // Each fresh Quick Train session is opt-in. Keep all saved voice and
        // guidance preferences, but never inherit a previous 'on' toggle.
        enabled = false
        distanceTriggerEnabled =
            settings.audioCoachDistanceTriggerEnabled
        timeTriggerEnabled =
            settings.audioCoachTimeTriggerEnabled
        distanceIntervalKilometers =
            settings.audioCoachDistanceIntervalKilometers
        timeIntervalMinutes =
            settings.audioCoachTimeIntervalMinutes
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

    func configuration(
        routeDistanceMeters: Double? = nil
    ) -> WatchAudioCoachConfiguration {
        WatchAudioCoachConfiguration(
            enabled: enabled,
            language: language,
            distanceIntervalMeters:
                enabled && distanceTriggerEnabled
                    ? distanceIntervalKilometers * 1_000
                    : nil,
            timeIntervalSeconds:
                enabled && timeTriggerEnabled
                    ? Double(timeIntervalMinutes * 60)
                    : nil,
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
        // Legacy planned workouts with an indoor block but no explicit
        // category were previously treadmill workouts: preserve their mode.
        if workout.resolvedWorkoutBlocks.contains(where: {
            $0.kind == .run && $0.isIndoor == true
        }) {
            return .treadmill
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
    var watchStartMode: WatchWorkoutStartMode = .immediate
    var routeWarmup: ATHLTHRouteWarmupConfiguration = .disabled
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
}

extension RunQuickStartConfiguration {
    func trainTogetherInvitePayload(
        savedRoutes: [TrainingRoute]
    ) -> SocialWorkoutInvitePayload {
        let resolvedRoute: TrainingRoute? = {
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
            routeID:
                resolvedRoute?.id ??
                workout?.routeID,
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
                    .disabled(playlist == nil)
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
    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var socialMode:
        SocialWorkoutParticipationMode =
            .physical
    @State private var selectedGearIDs: Set<UUID> = []
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

        // A planned indoor workout must start without GPS. Keep its
        // structured 4×4 steps, but do not let a saved route force outdoor mode.
        let plannedIndoor = RunEnvironment.forPlannedSession(plannedSession) == .treadmill
        let initialMode: RunQuickStartMode =
            initialWorkout != nil ? .structured :
            (initialRoute != nil && !plannedIndoor ? .route : .free)

        _environment = State(initialValue: plannedIndoor ? .treadmill : .outdoor)
        _mode = State(initialValue: initialMode)
        _selectedRoute = State(initialValue: plannedIndoor ? nil : initialRoute)
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
                    if isAdvancedSetup {
                        introCard
                        modeCard
                        runEnvironmentCard
                    } else {
                        ATHLTHRunBasicSetupView(
                            workoutName: $quickWorkoutName,
                            mode: $mode,
                            environment: $environment,
                            date: $quickDisplayDate,
                            selectedRouteTitle: selectedRoute?.title,
                            selectedWorkoutTitle: selectedWorkout?.title,
                            onChooseRoute: { showingRoutes = true },
                            onChooseWorkout: { showingRunningLibrary = true }
                        )
                    }

                    if let plannedSession {
                        PlannedQuickStartContextCard(workout: plannedSession)
                        ATHLTHRunQuickStartPlanPreview(
                            workout: nil, plannedSession: plannedSession
                        )
                    }

                    if mode == .route || mode == .structured {
                        if isAdvancedSetup {
                            selectionCard
                        } else {
                            basicSelectedContent
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
                    initialTitle: advancedWorkout?.title ??
                        selectedWorkout?.title ?? quickWorkoutName,
                    initialBlocks: advancedWorkout?.resolvedWorkoutBlocks ??
                        selectedWorkout.map {
                            ATHLTHQuickRunTimelineAdapter.editorBlocks(from: $0)
                        } ?? [],
                    initialRouteID: advancedWorkout?.routeID ??
                        selectedWorkout?.routeID,
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
            .onChange(of: environment) { _, newValue in
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

    private var introCard: some View {
        // Reuse the same editorial intro component as the Training Plan
        // builder instead of maintaining a separate photo-card treatment.
        ATHLTHPlanSectionIntro(
            eyebrow: ATHLTHLocalization.choose(
                english: "QUICK TRAIN", norwegian: "HURTIGTRENING"
            ),
            title: ATHLTHLocalization.choose(
                english: "Start run", norwegian: "Start løpeøkt"
            ),
            subtitle: ATHLTHLocalization.choose(
                english: "Choose the workout and where to run. Then start on iPhone or Apple Watch.",
                norwegian: "Velg løpetype og hvor du vil løpe. Start deretter med iPhone eller Apple Watch."
            ),
            icon: "figure.run"
        )
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

    private var runEnvironmentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ATHLTHLocalization.choose(
                english: "Where are you running?", norwegian: "Hvor løper du?"
            ))
            .font(.headline)
            .foregroundStyle(ATHLTHPlanDesign.ink)

            // The Training Plan selection cards are shared verbatim.
            ForEach(RunEnvironment.allCases) { option in
                ATHLTHPlanSelectionCard(
                    title: option.title,
                    subtitle: option.subtitle,
                    symbol: option.systemImage,
                    selected: environment == option,
                    accent: ATHLTHPlanDesign.accentInk
                ) {
                    environment = option
                }
            }

            if environment == .treadmill,
               let prior = phoneWorkout.lastTreadmillSpeedReference {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.format(
                            english: "Your previous logged belt speed: %.1f km/h",
                            norwegian: "Din sist registrerte møllehastighet: %.1f km/t",
                            prior.speed
                        ))
                        .font(.subheadline.weight(.semibold))
                        Text(ATHLTHLocalization.choose(
                            english: "Historical reference only. Set your actual belt speed during the workout.",
                            norwegian: "Kun historikk. Registrer faktisk møllehastighet under økten."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .padding(14)
                .athlthPlanCard(radius: 18)
            }
        }
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
            return advancedWorkout != nil || selectedWorkout != nil
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
        let runEnvironment = mode == .structured
            ? advancedWorkout.map { ATHLTHQuickRunTimelineAdapter.environment(for: $0) }
                ?? environment
            : environment
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
                        ? advancedWorkout?.resolvedWorkoutBlocks
                            .first(where: { $0.kind == .run })?
                            .treadmillInclinePercent ?? 0
                        : nil,
                audioCoach:
                    isAdvancedSetup
                        ? audioCoachConfiguration
                        : .disabled,
                routeAlerts:
                    routeAlerts,
                ghostTargetDurationSeconds:
                    isAdvancedSetup &&
                    guidanceRoute != nil
                        ? ghostDraft
                            .targetDuration
                        : nil,
                ghostUpdates:
                    isAdvancedSetup &&
                    guidanceRoute != nil &&
                    ghostDraft.enabled &&
                    ghostDraft.targetDuration != nil &&
                    ghostDraft.updatesEnabled
                        ? settings
                            .ghostRaceAudioConfiguration
                        : nil,
                autoPauseEnabled:
                    environment == .outdoor &&
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
        configuration.advancedWorkout = mode == .structured ? advancedWorkout : nil
        configuration.routeWarmup = mode == .route ? routeWarmup : .disabled
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
            parts.append("Route Guardian")
        }

        if ghostDraft.enabled,
           guidanceRoute != nil {
            parts.append("Ghost Updates")
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
            routeDistanceMeters: routeDistanceMeters
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
    @State private var audioCoachDraft = AudioCoachDraft()
    @State private var didLoadAudioCoachDefaults = false
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
                VStack(spacing: 16) {
                    ATHLTHPlanSurface(density: .compact) {
                        HStack(spacing: 14) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(width: 54, height: 54)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(
                                        cornerRadius: 16
                                    )
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Free Walk")
                                    .font(.title3.weight(.bold))

                                Text(
                                    "Choose whether this walk should be recorded with iPhone or Apple Watch."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                isAdvancedSetup.toggle()
                            } label: {
                                Text(
                                    isAdvancedSetup
                                        ? ATHLTHLocalization.choose(
                                            english: "Advanced",
                                            norwegian: "Avansert"
                                        )
                                        : "Basic"
                                )
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 11)
                                .frame(height: 34)
                                .foregroundStyle(
                                    isAdvancedSetup
                                        ? Color.white
                                        : ATHLTHTheme.accentDeep
                                )
                                .background(
                                    isAdvancedSetup
                                        ? ATHLTHTheme.accent
                                        : ATHLTHTheme.accentSoft,
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let plannedSession {
                        PlannedQuickStartContextCard(workout: plannedSession)
                    }

                    WorkoutGearSelectionCard(
                        selectedGearIDs: $selectedGearIDs,
                        activity: .walking
                    )

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
        let configuration = WalkQuickStartConfiguration(
                captureDevice: device,
                audioCoach:
                    isAdvancedSetup &&
                    session.canAccess(.audioCoach)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    QuickTrainingHeroCard(
                        imageName:
                            "StrengthQuickHero",
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Start Strength",
                                norwegian:
                                    "Start styrkeøkt"
                            ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "Add exercises first for a focused session, or choose a completely open workout.",
                                norwegian:
                                    "Legg inn øvelser først for en fokusert økt, eller velg en helt åpen økt."
                            ),
                        icon:
                            "figure.strengthtraining.traditional"
                    )

                    NavigationLink {
                        StrengthQuickBuilderView { workout in
                            social.prepareQuickTrainFriendsForLaunch()
                            onChoose(workout)
                            dismiss()
                        }
                    } label: {
                        choiceCard(
                            title:
                                ATHLTHLocalization.choose(
                                    english:
                                        "Add exercises first",
                                    norwegian:
                                        "Legg til øvelser først"
                                ),
                            subtitle:
                                ATHLTHLocalization.choose(
                                    english:
                                        "Build the workout before you start. During training ATHLTH shows one exercise at a time.",
                                    norwegian:
                                        "Bygg økten før du starter. Under trening viser ATHLTH én øvelse om gangen."
                                ),
                            icon:
                                "list.bullet.clipboard.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        social.prepareQuickTrainFriendsForLaunch()
                        onChoose(emptySession)
                        dismiss()
                    } label: {
                        choiceCard(
                            title:
                                ATHLTHLocalization.choose(
                                    english:
                                        "Train without a plan",
                                    norwegian:
                                        "Tren uten plan"
                                ),
                            subtitle:
                                ATHLTHLocalization.choose(
                                    english:
                                        "Start the timer without preloading exercises. You can add one while training if you want.",
                                    norwegian:
                                        "Start tidtaking uten å legge inn øvelser på forhånd. Du kan legge til en øvelse underveis hvis du vil."
                                ),
                            icon:
                                "figure.strengthtraining.traditional"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Strength",
                    norwegian: "Styrke"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var emptySession: PlannedSession {
        PlannedSession(
            id: UUID(),
            title:
                ATHLTHLocalization.choose(
                    english: "Strength",
                    norwegian: "Styrke"
                ),
            kind: .strength,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes:
                "Open strength session · exercises can be added during training",
            runningWorkout: nil
        )
    }

    private func choiceCard(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        ATHLTHCard {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 52, height: 52)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 15)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
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

struct AudioCoachSetupCard: View {
    @Binding var draft: AudioCoachDraft
    let showRouteOptions: Bool
    let showStructuredOptions: Bool
    @State private var showAdvancedSettings = false

    var body: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text("Audio Coach")
                            .font(.headline)

                        Text("ATHLTH+")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(
                                ATHLTHTheme.premiumGold
                            )
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                ATHLTHTheme.premiumGoldSoft,
                                in: Capsule()
                            )
                    }

                    Text(
                        ATHLTHLocalization.choose(
                            english: "Choose how much guidance you want during your workout.",
                            norwegian: "Velg hvor mye veiledning du ønsker under økten."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $draft.enabled)
                    .labelsHidden()
            }

            if draft.enabled {
                VStack(alignment: .leading, spacing: 14) {
                    Divider()

                    Text(ATHLTHLocalization.choose(
                        english: "How much guidance?",
                        norwegian: "Hvor mye veiledning?"
                    ))
                    .font(.subheadline.weight(.semibold))

                    HStack(spacing: 7) {
                        ForEach(ATHLTHCoachExperiencePreset.allCases) { preset in
                            Button {
                                draft.applyExperience(preset)
                            } label: {
                                VStack(spacing: 5) {
                                    Text(preset.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(preset.subtitle)
                                        .font(.caption2)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.85)
                                }
                                .frame(maxWidth: .infinity, minHeight: 69)
                                .padding(.horizontal, 5)
                                .foregroundStyle(draft.experiencePreset == preset
                                    ? Color.white : ATHLTHTheme.primaryText)
                                .background(draft.experiencePreset == preset
                                    ? ATHLTHTheme.accentDeep : ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(
                                draft.experiencePreset == preset ? .isSelected : []
                            )
                        }
                    }

                    if draft.experiencePreset == nil {
                        Text(ATHLTHLocalization.choose(
                            english: "Your custom setup is preserved until you select a level.",
                            norwegian: "Ditt tilpassede oppsett beholdes til du velger et nivå."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        ForEach([
                            ATHLTHCoachSpeechStyle.balanced,
                            .motivating
                        ]) { style in
                            Button {
                                draft.speechStyle = style
                            } label: {
                                Label(style.title, systemImage: style == .motivating
                                    ? "flame.fill" : "waveform")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .foregroundStyle(draft.speechStyle == style
                                        ? Color.white : ATHLTHTheme.primaryText)
                                    .background(draft.speechStyle == style
                                        ? ATHLTHTheme.accentDeep : ATHLTHTheme.accentSoft,
                                        in: RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAdvancedSettings.toggle()
                        }
                    } label: {
                        HStack {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "More settings", norwegian: "Flere innstillinger"
                                ),
                                systemImage: "slider.horizontal.3"
                            )
                            Spacer()
                            Image(systemName: showAdvancedSettings
                                ? "chevron.up" : "chevron.down")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)

                    if showAdvancedSettings {
                    Divider()

                    Text("WHEN TO SPEAK")
                        .font(.caption2.weight(.bold))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Distance updates",
                        isOn: $draft.distanceTriggerEnabled
                    )

                    if draft.distanceTriggerEnabled {
                        HStack {
                            Text("Every")
                            Spacer()
                            Picker(
                                "Distance interval",
                                selection:
                                    $draft.distanceIntervalKilometers
                            ) {
                                Text("0.5 km").tag(0.5)
                                Text("1 km").tag(1.0)
                                Text("2 km").tag(2.0)
                                Text("5 km").tag(5.0)
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Toggle(
                        "Time updates",
                        isOn: $draft.timeTriggerEnabled
                    )

                    if draft.timeTriggerEnabled {
                        HStack {
                            Text("Every")
                            Spacer()
                            Picker(
                                "Time interval",
                                selection:
                                    $draft.timeIntervalMinutes
                            ) {
                                Text("5 min").tag(5)
                                Text("10 min").tag(10)
                                Text("15 min").tag(15)
                                Text("30 min").tag(30)
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Divider()

                    Text("WHAT TO ANNOUNCE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Distance",
                        isOn: $draft.announceDistance
                    )
                    Toggle(
                        "Elapsed time",
                        isOn: $draft.announceElapsedTime
                    )
                    Toggle(
                        "Average pace",
                        isOn: $draft.announceAveragePace
                    )
                    Toggle(
                        "Current time",
                        isOn: $draft.announceClockTime
                    )
                    Toggle(
                        "Heart rate",
                        isOn: $draft.announceHeartRate
                    )

                    if showRouteOptions {
                        Divider()

                        Text("ROUTE")
                            .font(.caption2.weight(.bold))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)

                        Toggle(
                            "Remaining distance",
                            isOn:
                                $draft
                                    .announceRemainingRouteDistance
                        )
                        Toggle(
                            "Estimated time remaining",
                            isOn:
                                $draft
                                    .announceEstimatedRemainingRouteTime
                        )
                    }

                    if showStructuredOptions {
                        Divider()

                        Text("STRUCTURED WORKOUT")
                            .font(.caption2.weight(.bold))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)

                        Toggle(
                            "Current / next step",
                            isOn:
                                $draft
                                    .announceCurrentWorkoutStep
                        )
                        Toggle(
                            "Remaining step time",
                            isOn:
                                $draft
                                    .announceRemainingStepTime
                        )
                        Toggle(
                            "Remaining step distance",
                            isOn:
                                $draft
                                    .announceRemainingStepDistance
                        )
                    }

                    Divider()

                    Text("MUSIC & OTHER AUDIO")
                        .font(.caption2.weight(.bold))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Lower music while coach speaks",
                        isOn: $draft.duckOtherAudio
                    )

                    Text(
                        draft.duckOtherAudio
                            ? "Spotify and other audio are reduced only while the coach is speaking."
                            : "Coach speech mixes with music at its current level."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    Divider()

                    HStack {
                        Text("Language")
                        Spacer()
                        Picker(
                            "Language",
                            selection: $draft.language
                        ) {
                            ForEach(
                                WatchAudioCoachLanguage.allCases,
                                id: \.rawValue
                            ) { language in
                                Text(language.title)
                                    .tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(
                            of: draft.language
                        ) { _, _ in
                            draft.voiceIdentifier = nil
                        }
                    }

                    Text(
                        ATHLTHLocalization.choose(
                            english: "Settings defaults are loaded automatically. Changes here affect only this workout.",
                            norwegian: "Standardinnstillingene lastes automatisk. Endringer her gjelder bare denne økten."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 10)
            }
        }
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
