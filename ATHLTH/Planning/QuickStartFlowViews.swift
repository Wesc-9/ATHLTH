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
    var announceWorkoutStart = true
    var announcePauseResume = true
    var announceWorkoutComplete = true
    var guidanceQuietPeriodSeconds:
        TimeInterval = 10

    var language: WatchAudioCoachLanguage = .system

    @MainActor
    mutating func load(from settings: AppSettingsStore) {
        enabled = settings.audioCoachEnabledByDefault
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
        case .free: return "Free Run"
        case .route: return "Route"
        case .structured: return "Workout"
        }
    }

    var subtitle: String {
        switch self {
        case .free:
            return "Just start running. No route or target required."
        case .route:
            return "Follow one of your saved ATHLTH routes."
        case .structured:
            return "Choose a workout from the running library."
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

struct RunQuickStartConfiguration {
    let mode: RunQuickStartMode
    let route: TrainingRoute?
    let workout: RunningWorkoutTemplate?
    let captureDevice: WorkoutCaptureDevice
    let audioCoach: WatchAudioCoachConfiguration
    let routeAlerts: WatchRouteAlertConfiguration
    let ghostTargetDurationSeconds: TimeInterval?
    let ghostUpdates: WatchGhostRaceAudioConfiguration?
    let autoPauseEnabled: Bool
    let friends: [SocialProfileCard]
    let gearIDs: Set<UUID>

    var title: String {
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
    let friends: [SocialProfileCard]
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
                    workout?.routeID
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
        snapshot.runningWorkout = workout
        snapshot.runningWorkouts =
            workout.map { [$0] }
        snapshot.audioCoachConfiguration =
            audioCoach
        snapshot.autoPauseEnabled =
            autoPauseEnabled

        return SocialWorkoutInvitePayload(
            workout: snapshot,
            route: resolvedRoute,
            routeAlerts: routeAlerts
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
            workout: snapshot
        )
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

struct QuickStartWorkoutDeviceCard: View {
    @Binding var selection: WorkoutCaptureDevice
    let watchConnected: Bool
    let iPhoneEnabled: Bool
    let iPhoneSubtitle: String

    var body: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(title: "Workout device")

            VStack(spacing: 10) {
                deviceRow(
                    title: "iPhone",
                    subtitle: iPhoneSubtitle,
                    icon: "iphone",
                    selected: selection == .iPhone,
                    disabled: !iPhoneEnabled
                ) {
                    selection = .iPhone
                }

                deviceRow(
                    title: "Apple Watch",
                    subtitle: watchConnected
                        ? "Record with Apple Watch, including live workout metrics."
                        : "Finish Apple Watch setup in Settings to use this option.",
                    icon: "applewatch",
                    selected: selection == .appleWatch,
                    disabled: !watchConnected
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

struct RunQuickStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var gear: ProfileGearStore

    let trainingDeviceProvider: TrainingDeviceProvider
    let watchConnected: Bool
    let onStart: (RunQuickStartConfiguration) -> Void

    @State private var mode: RunQuickStartMode
    @State private var selectedRoute: TrainingRoute?
    @State private var selectedWorkout: RunningWorkoutTemplate?
    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var selectedGearIDs: Set<UUID> = []
    @State private var captureDevice: WorkoutCaptureDevice
    @StateObject private var routeLocationProbe =
        QuickStartRouteLocationProbe()

    init(
        trainingDeviceProvider: TrainingDeviceProvider,
        watchConnected: Bool,
        initialRoute: TrainingRoute? = nil,
        initialWorkout:
            RunningWorkoutTemplate? = nil,
        onStart: @escaping (RunQuickStartConfiguration) -> Void
    ) {
        self.trainingDeviceProvider = trainingDeviceProvider
        self.watchConnected = watchConnected
        self.onStart = onStart

        let initialMode:
            RunQuickStartMode =
                initialWorkout != nil
                    ? .structured
                    : initialRoute != nil
                        ? .route
                        : .free

        _mode = State(
            initialValue: initialMode
        )
        _selectedRoute = State(
            initialValue: initialRoute
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

    @State private var audioCoachDraft = AudioCoachDraft()
    @State private var routeGuardianDraft =
        RouteGuardianDraft()
    @State private var ghostDraft =
        GhostQuickStartDraft()
    @State private var didLoadAudioCoachDefaults = false
    @State private var didLoadGuidanceDefaults = false
    @State private var isAdvancedSetup = false
    @State private var autoPausePreference:
        WorkoutAutoPausePreference = .appDefault

    private var canStart: Bool {
        if captureDevice == .appleWatch,
           !watchConnected {
            return false
        }

        switch mode {
        case .free:
            return true
        case .route:
            return selectedRoute != nil
        case .structured:
            return selectedWorkout != nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    introCard
                    modeCard

                    runDeviceCard

                    selectionCard

                    WorkoutGearSelectionCard(
                        selectedGearIDs: $selectedGearIDs,
                        activity: .running
                    )

                    if isAdvancedSetup {
                        VStack(spacing: 12) {
                            QuickStartAutoPauseCard(
                                preference: $autoPausePreference,
                                appDefaultEnabled:
                                    settings.autoPauseOutdoorWorkouts
                            )

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
                                ATHLTHCard {
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
                                                ATHLTHLocalization.choose(
                                                    english:
                                                        "Guidance & Alerts",
                                                    norwegian:
                                                        "Veiledning og varsler"
                                                )
                                            )
                                            .font(
                                                .subheadline
                                                    .weight(
                                                        .semibold
                                                    )
                                            )

                                            Text(
                                                guidanceSummary
                                            )
                                            .font(.caption)
                                            .foregroundStyle(
                                                .secondary
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
                                        .foregroundStyle(
                                            .secondary
                                        )
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            ATHLTHCard {
                                WorkoutFriendPicker(
                                    selectedFriendIDs:
                                        $selectedFriendIDs
                                )
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
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme.canvasTop,
                        ATHLTHTheme.canvasBottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
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
                        selectedWorkout = workout
                        showingRunningLibrary = false
                    }
                }
            }
            .task {
                if !didLoadAudioCoachDefaults {
                    audioCoachDraft.load(from: settings)
                    didLoadAudioCoachDefaults = true
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
        }
    }

    private var introCard: some View {
        ZStack {
            Image(
                "StrengthPostWorkoutHero"
            )
            .resizable()
            .scaledToFill()
            .frame(height: 118)
            .clipped()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.68),
                    Color.black.opacity(0.28),
                    Color.black.opacity(0.08)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Start Run",
                        norwegian: "Start løpeøkt"
                    )
                )
                .font(
                    .title2.weight(
                        .bold
                    )
                )
                .foregroundStyle(.white)
                .lineLimit(1)

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            isAdvancedSetup
                                ? "Routes, guidance and social options."
                                : "Fast setup with the essentials.",
                        norwegian:
                            isAdvancedSetup
                                ? "Ruter, veiledning og sosiale valg."
                                : "Raskt oppsett med det viktigste."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    Color.white.opacity(
                        0.84
                    )
                )
                .lineLimit(2)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(16)
        }
        .frame(height: 118)
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
                Color.white.opacity(
                    0.22
                ),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(
                    0.08
                ),
            radius: 16,
            y: 8
        )
    }

    private var runSetupModeButton: some View {
        Button {
            isAdvancedSetup.toggle()
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
                        : "Basic"
                )
                .font(
                    .caption
                        .weight(.bold)
                )
            }
            .foregroundStyle(
                isAdvancedSetup
                    ? Color.white
                    : ATHLTHTheme.primaryText
            )
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                isAdvancedSetup
                    ? ATHLTHTheme.vitality
                    : Color.primary.opacity(
                        0.055
                    ),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        Color.black.opacity(
                            0.045
                        ),
                        lineWidth: 0.7
                    )
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

    private var runDeviceCard: some View {
        ATHLTHCard {
            HStack(spacing: 8) {
                RoundedRectangle(
                    cornerRadius: 2,
                    style: .continuous
                )
                .fill(
                    ATHLTHTheme.premiumGold
                )
                .frame(
                    width: 4,
                    height: 26
                )

                Text(
                    ATHLTHLocalization.choose(
                        english: "Workout device",
                        norwegian: "Treningsenhet"
                    )
                )
                .font(
                    .title3.weight(.bold)
                )

                Spacer()
            }

            HStack(spacing: 10) {
                runDeviceTile(
                    title: "iPhone",
                    icon: "iphone",
                    selected:
                        captureDevice == .iPhone,
                    disabled: false
                ) {
                    captureDevice = .iPhone
                }

                runDeviceTile(
                    title: "Apple Watch",
                    icon: "applewatch",
                    selected:
                        captureDevice ==
                            .appleWatch,
                    disabled:
                        !watchConnected
                ) {
                    captureDevice =
                        .appleWatch
                }
            }
            .padding(.top, 10)

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "This choice applies only to this workout.",
                    norwegian:
                        "Valget gjelder bare denne økten."
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
    }

    private func runDeviceTile(
        title: String,
        icon: String,
        selected: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 22,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        selected
                            ? Color.white
                            : disabled
                                ? Color.secondary
                                : ATHLTHTheme
                                    .primaryText
                    )

                Text(title)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        selected
                            ? Color.white
                            : disabled
                                ? ATHLTHTheme
                                    .mutedText
                                : ATHLTHTheme
                                    .primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(
                        0.82
                    )

                Image(
                    systemName:
                        selected
                            ? "checkmark.circle.fill"
                            : "circle"
                )
                .font(.caption)
                .foregroundStyle(
                    selected
                        ? Color.white
                        : Color.secondary
                )
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 118
            )
            .background(
                selected
                    ? ATHLTHTheme
                        .accentDeep
                    : Color.primary
                        .opacity(0.025),
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    selected
                        ? ATHLTHTheme
                            .accentDeep
                            .opacity(0.20)
                        : Color.black
                            .opacity(0.045),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(
            disabled
                ? 0.60
                : 1
        )
    }

    private var modeCard: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(
                title: "Run type",
                actionTitle: "Choose one"
            )

            VStack(spacing: 8) {
                ForEach(RunQuickStartMode.allCases) { option in
                    Button {
                        mode = option
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(
                                    mode == option
                                        ? Color.white
                                        : ATHLTHTheme.accent
                                )
                                .frame(width: 40, height: 40)
                                .background(
                                    mode == option
                                        ? ATHLTHTheme.accent
                                        : ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )

                                Text(option.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()

                            Image(
                                systemName:
                                    mode == option
                                        ? "checkmark.circle.fill"
                                        : "circle"
                            )
                            .foregroundStyle(
                                mode == option
                                    ? ATHLTHTheme.accent
                                    : Color.secondary
                            )
                        }
                        .padding(10)
                        .background(
                            mode == option
                                ? ATHLTHTheme.accentSoft.opacity(0.55)
                                : Color.primary.opacity(0.02),
                            in: RoundedRectangle(cornerRadius: 15)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var selectionCard: some View {
        switch mode {
        case .free:
            ATHLTHCard {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(ATHLTHTheme.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("No destination. No target.")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            "ATHLTH records your run, GPS route, time, distance and available heart-rate data."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }

        case .route:
            ATHLTHCard {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            selectedRoute?.title ??
                                "Choose a saved route"
                        )
                        .font(.headline)

                        if let selectedRoute {
                            Text(
                                String(
                                    format: "%.1f km · saved route",
                                    selectedRoute.distanceKilometers
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text(
                                session.savedRoutes.isEmpty
                                    ? "You do not have any saved routes yet."
                                    : "\(session.savedRoutes.count) routes available"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        showingRoutes = true
                    } label: {
                        Text(
                            selectedRoute == nil
                                ? "Choose"
                                : "Change"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(ATHLTHTheme.accent)
                }

                if let distance =
                        distanceToSelectedRouteStart,
                   distance > 250 {
                    Divider()
                        .padding(.vertical, 8)

                    HStack(
                        alignment: .top,
                        spacing: 10
                    ) {
                        Image(
                            systemName:
                                "location.circle.fill"
                        )
                        .foregroundStyle(
                            ATHLTHTheme.premiumGold
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
                                    .weight(.semibold)
                            )

                            Text(
                                "You can start anyway, but ATHLTH will mark your route progress only when you reach the course."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Button {
                                openDirectionsToRouteStart()
                            } label: {
                                Label(
                                    "Directions to start",
                                    systemImage:
                                        "arrow.triangle.turn.up.right.diamond.fill"
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.top, 3)
                        }

                        Spacer(minLength: 0)
                    }
                }

                if session.savedRoutes.isEmpty {
                    NavigationLink {
                        RunRouteBuilderView()
                    } label: {
                        Label(
                            "Create Route",
                            systemImage: "plus"
                        )
                    }
                    .padding(.top, 10)
                }
            }

        case .structured:
            ATHLTHCard {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            selectedWorkout?.title ??
                                "Choose a running workout"
                        )
                        .font(.headline)

                        Text(
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
                            selectedWorkout == nil
                                ? "Choose"
                                : "Change"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(ATHLTHTheme.accent)
                }

                if let workout = selectedWorkout {
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
        startButton
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(
                .ultraThinMaterial
            )
            .overlay(
                alignment: .top
            ) {
                Divider()
                    .opacity(0.35)
            }
    }

    private var startButton: some View {
        Button {
            let friends =
                isAdvancedSetup
                    ? social.trainingPartners
                        .filter {
                            selectedFriendIDs
                                .contains(
                                    $0.userID
                                )
                        }
                    : []

            var routeAlerts =
                routeGuardianDraft
                    .configuration
            if !isAdvancedSetup {
                routeAlerts.enabled = false
            }

            onStart(
                RunQuickStartConfiguration(
                    mode: mode,
                    route:
                        mode == .route
                            ? selectedRoute
                            : nil,
                    workout:
                        mode == .structured
                            ? selectedWorkout
                            : nil,
                    captureDevice: captureDevice,
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
                        ghostDraft.updatesEnabled
                            ? settings
                                .ghostRaceAudioConfiguration
                            : nil,
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
                    friends: friends,
                    gearIDs: selectedGearIDs
                )
            )
            dismiss()
        } label: {
            Label(
                startButtonTitle,
                systemImage: "play.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(ATHLTHTheme.vitality)
        .disabled(!canStart)
    }

    private var startButtonTitle: String {
        if captureDevice == .iPhone {
            switch mode {
            case .free:
                return "Start Free Run on iPhone"
            case .route:
                return "Start Route on iPhone"
            case .structured:
                return "Start Workout on iPhone"
            }
        }

        guard watchConnected else {
            return "Apple Watch Required"
        }

        switch mode {
        case .free: return "Start Free Run on Watch"
        case .route: return "Start Route on Watch"
        case .structured: return "Start Workout on Watch"
        }
    }

    private var guidanceRoute:
        TrainingRoute?
    {
        if mode == .route {
            return selectedRoute
        }

        guard mode == .structured,
              let routeID =
                selectedWorkout?.routeID
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

    let trainingDeviceProvider: TrainingDeviceProvider
    let watchConnected: Bool
    let onStart: (WalkQuickStartConfiguration) -> Void

    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var selectedGearIDs: Set<UUID> = []
    @State private var captureDevice: WorkoutCaptureDevice = .iPhone
    @State private var audioCoachDraft = AudioCoachDraft()
    @State private var didLoadAudioCoachDefaults = false
    @State private var isAdvancedSetup = false
    @State private var autoPausePreference:
        WorkoutAutoPausePreference = .appDefault

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ATHLTHCard {
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

                    QuickStartWorkoutDeviceCard(
                        selection: $captureDevice,
                        watchConnected: watchConnected,
                        iPhoneEnabled: true,
                        iPhoneSubtitle:
                            "Keep your iPhone with you to record GPS distance, pace and time."
                    )

                    WorkoutGearSelectionCard(
                        selectedGearIDs: $selectedGearIDs,
                        activity: .walking
                    )

                    if isAdvancedSetup {
                        QuickStartAutoPauseCard(
                            preference: $autoPausePreference,
                            appDefaultEnabled:
                                settings.autoPauseOutdoorWorkouts
                        )

                        NavigationLink {
                            PerWorkoutAudioCoachView(
                                draft:
                                    $audioCoachDraft,
                                showRouteOptions: false,
                                showStructuredOptions: false
                            )
                        } label: {
                            ATHLTHCard {
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
                        ATHLTHCard {
                            WorkoutFriendPicker(
                                selectedFriendIDs: $selectedFriendIDs
                            )
                        }
                    }

                    Button {
                        let friends = social.trainingPartners.filter {
                            selectedFriendIDs.contains($0.userID)
                        }

                        onStart(
                            WalkQuickStartConfiguration(
                                captureDevice: captureDevice,
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
                                friends:
                                    isAdvancedSetup
                                        ? friends
                                        : [],
                                gearIDs: selectedGearIDs
                            )
                        )
                        dismiss()
                    } label: {
                        Label(
                            captureDevice == .appleWatch
                                ? (watchConnected
                                    ? "Start Walk on Watch"
                                    : "Apple Watch Required")
                                : "Start on iPhone",
                            systemImage:
                                captureDevice == .appleWatch
                                    ? "applewatch"
                                    : "iphone"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ATHLTHTheme.accent)
                    .disabled(
                        captureDevice == .appleWatch && !watchConnected
                    )
                }
                .padding()
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
            .task {
                if !didLoadAudioCoachDefaults {
                    audioCoachDraft.load(from: settings)
                    didLoadAudioCoachDefaults = true
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

}

struct StrengthQuickStartSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onChoose: (PlannedSession) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ATHLTHCard {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Start Strength")
                                .font(.title2.weight(.bold))
                            Text(
                                "Start completely open, or build the session right before you train."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        onChoose(emptySession)
                        dismiss()
                    } label: {
                        choiceCard(
                            title: "Start Empty",
                            subtitle:
                                "Start the workout now. Add exercises, sets, reps and weight while you train.",
                            icon: "play.circle.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        StrengthQuickBuilderView { workout in
                            onChoose(workout)
                            dismiss()
                        }
                    } label: {
                        choiceCard(
                            title: "Build Before Start",
                            subtitle:
                                "Choose exercises and targets now, then start the finished setup.",
                            icon: "list.bullet.clipboard.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationTitle("Quick Strength")
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
            title: "Freestyle Strength",
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

    var body: some View {
        Form {
            Section("Workout") {
                TextField("Workout name", text: $title)

                Text(
                    "Build only as much as you want. Every exercise can still be changed or added after the workout starts."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Exercises") {
                if exercises.isEmpty {
                    Text(
                        "No exercises yet. Add one below, or go back and choose Start Empty."
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
                        "Continue to Start",
                        systemImage: "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .disabled(
                    title.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Build Workout")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExerciseLibrary) {
            NavigationStack {
                ExerciseLibraryView(
                    selectionTitle: "Add to Workout"
                ) { entry in
                    addExercise(entry.exercise)
                    showingExerciseLibrary = false
                }
            }
        }
        .sheet(item: $exerciseBeingEdited) { exercise in
            PlannedExerciseEditorView(
                exercise: exercise
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

    private func addExercise(
        _ exercise: Exercise
    ) {
        exercises.append(
            PlannedExercise(
                id: UUID(),
                exerciseID: exercise.id,
                embeddedExercise: exercise.snapshot,
                sets: 3,
                reps: 8,
                targetWeightKilograms: nil,
                targetRPE: nil,
                restSeconds: 90,
                notes: nil,
                targetRIR: nil,
                supersetGroupID: nil,
                progression:
                    StrengthProgressionRule.none
            )
        )
    }

    private func exerciseSummary(
        _ exercise: PlannedExercise
    ) -> String {
        var parts = [
            "\(exercise.sets) × \(exercise.reps ?? 0)"
        ]

        if let weight = exercise.targetWeightKilograms {
            parts.append(
                String(format: "%.1f kg", weight)
            )
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
                        "Choose when iPhone or Apple Watch speaks and exactly what it tells you."
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
                        "Your Settings defaults are loaded here automatically. Changes on this screen apply only to this workout."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
