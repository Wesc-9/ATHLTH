import SwiftUI

struct WorkoutStartOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var appSession: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var spotify: SpotifyPlaybackStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore

    let session: PlannedSession
    let trainingDeviceProvider: TrainingDeviceProvider
    let watchConnected: Bool
    let onStart: (
        PlannedSession,
        WorkoutCaptureDevice,
        StrengthTrackingMode,
        [SocialProfileCard],
        SocialWorkoutParticipationMode,
        WatchAudioCoachConfiguration,
        StrengthAdvancedConfiguration
    ) async -> String?

    @State private var trackingMode: StrengthTrackingMode
    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var socialMode:
        SocialWorkoutParticipationMode =
            .physical
    @State private var audioCoachDraft = AudioCoachDraft()
    @State private var audioCoachLoaded = false
    @State private var strengthAudioCoach =
        StrengthAudioCoachConfiguration()
    @State private var restCues =
        StrengthRestCueConfiguration()
    @State private var selectedSpotifyPlaylist:
        SpotifyPlaylistReference?
    @State private var spotifyAutoplay = false
    @State private var keepScreenAwake = false
    @State private var inputMode:
        WatchStrengthInputMode = .both
    @State private var effortMetric:
        StrengthEffortMetric = .off
    @State private var configuredExercises:
        [PlannedExercise]
    @State private var showingExerciseLibrary = false
    @State private var showingAIExercisePlanner = false
    @State private var exerciseBeingEdited:
        PlannedExercise?
    @State private var pendingTreadmillSetup: PlannedExercise?
    @State private var selectedTrainingPlace: ATHLTHTrainingPlace?
    @State private var showingTrainingPlacePicker = false
    @State private var launchInProgress = false
    @State private var inlineLaunchError: String?

    @State private var showingSpotifyPicker = false
    @State private var didLoadSpotifySelection = false
    @State private var showingAudioCoachSettings = false
    @State private var showingRestCueSettings = false

    @State private var showingDisplayControls = false
    @State private var targetHeartRateZone: Int?


    init(
        session: PlannedSession,
        trainingDeviceProvider: TrainingDeviceProvider,
        watchConnected: Bool,
        defaultCapture: WorkoutCapturePreference,
        defaultTracking: StrengthTrackingPreference,
        onStart: @escaping (
            PlannedSession,
            WorkoutCaptureDevice,
            StrengthTrackingMode,
            [SocialProfileCard],
            SocialWorkoutParticipationMode,
            WatchAudioCoachConfiguration,
            StrengthAdvancedConfiguration
    ) async -> String?
    ) {
        self.session = session
        self.trainingDeviceProvider = trainingDeviceProvider
        self.watchConnected = watchConnected
        self.onStart = onStart

        let savedAdvanced =
            StrengthAdvancedConfiguration
                .savedDefaults()

        _trackingMode = State(
            initialValue: defaultTracking == .advanced ? .advanced : .simple
        )
        _configuredExercises = State(
            initialValue: session.exercises
        )
        _targetHeartRateZone = State(
            initialValue: session.targetAlertConfiguration?.heartRateZone
        )
        _selectedTrainingPlace = State(initialValue: session.plannedTrainingPlace)
        _selectedSpotifyPlaylist = State(
            initialValue:
                session.spotifyPlaylist ??
                savedAdvanced.spotifyPlaylist
        )
        _spotifyAutoplay = State(
            initialValue:
                session.spotifyAutoplayOnStart ??
                (
                    session.spotifyPlaylist != nil
                        ? true
                        : savedAdvanced.spotifyAutoplay
                )
        )
        // Preserve the saved voice and cue preferences, but require an
        // explicit opt-in to spoken coaching for every new strength session.
        var sessionCoach = savedAdvanced.audioCoach
        sessionCoach.enabled = false
        _strengthAudioCoach = State(
            initialValue: sessionCoach
        )
        _restCues = State(
            initialValue:
                savedAdvanced.restCues
        )
        _keepScreenAwake = State(
            initialValue:
                savedAdvanced.keepScreenAwake
        )
        _inputMode = State(
            initialValue:
                savedAdvanced.inputMode
        )
        _effortMetric = State(
            initialValue:
                savedAdvanced.effortMetric ??
                .off
        )
    }

    private var appleWatchSelectable: Bool {
        ATHLTHDeviceRole.isIPad ||
            watchConnected
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    strengthIntroCard

                    // Exercise planning belongs in both Basic and Advanced.
                    // Advanced should add optional workout controls, not hide the
                    // core ability to build the strength session before starting.
                    exerciseSelectionCard
                    ATHLTHPlanSurface(density: .compact) {
                        Button {
                            showingTrainingPlacePicker = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ATHLTHLocalization.choose(
                                        english: "Training place",
                                        norwegian: "Treningssted"
                                    ))
                                    .font(.subheadline.weight(.semibold))
                                    Text(selectedTrainingPlace?.name ??
                                        ATHLTHLocalization.choose(
                                            english: "Optional · choose a venue",
                                            norwegian: "Valgfritt · velg sted"
                                        ))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }

                    ATHLTHPlanSurface(density: .compact) {
                        HStack(spacing: 10) {
                            Image(systemName: "heart.text.square")
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Heart-rate zone target",
                                    norwegian: "Målpulssone"
                                ))
                                .font(.subheadline.weight(.semibold))
                                Text(ATHLTHLocalization.choose(
                                    english: "Optional · set before starting",
                                    norwegian: "Valgfritt · velges før økten"
                                ))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }

                            Spacer()

                            Menu {
                                Button(ATHLTHLocalization.choose(
                                    english: "No target", norwegian: "Ingen mål"
                                )) { targetHeartRateZone = nil }
                                ForEach(1...5, id: \.self) { zone in
                                    Button("Sone \(zone)") {
                                        targetHeartRateZone = zone
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(targetHeartRateZone.map { "Sone \($0)" } ??
                                        ATHLTHLocalization.choose(
                                            english: "No target", norwegian: "Ingen mål"
                                        ))
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                .frame(minHeight: 44)
                            }
                        }
                    }

                    // Same immediate avatar row as Quick Run and Quick Walk.
                    ATHLTHPlanSurface(ghost: false, density: .compact) {
                        VStack(alignment: .leading, spacing: 10) {
                            WorkoutFriendPicker(
                                selectedFriendIDs: $selectedFriendIDs
                            )
                            if !selectedFriendIDs.isEmpty {
                                Divider()
                                WorkoutSocialModePicker(mode: $socialMode)
                            }
                        }
                    }

                    // Audio Coach is a core workout option, not an
                    // advanced-only control. Basic users may enable simple
                    // spoken guidance without changing tracking mode.
                    advancedOptionButton(
                        title: "Audio Coach",
                        subtitle:
                            strengthAudioCoach.enabled
                                ? ATHLTHLocalization.choose(
                                    english: "Strength coaching on · adjust",
                                    norwegian: "Styrkeveiledning på · juster"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Off · tap to enable",
                                    norwegian: "Av · trykk for å aktivere"
                                ),
                        icon: "waveform.and.mic",
                        tint: ATHLTHTheme.premiumGold
                    ) {
                        showingAudioCoachSettings = true
                    }

                    if trackingMode == .advanced {
                        VStack(spacing: 9) {
                            advancedOptionButton(
                                title: "Spotify",
                                subtitle:
                                    spotifySummary,
                                icon: "music.note",
                                tint: Color.green
                            ) {
                                showingSpotifyPicker = true
                            }

                            advancedOptionButton(
                                title:
                                    ATHLTHLocalization.choose(
                                        english: "Rest & cues",
                                        norwegian: "Hvile & varsler"
                                    ),
                                subtitle:
                                    restCueSummary,
                                icon: "timer",
                                tint: ATHLTHTheme.accent
                            ) {
                                showingRestCueSettings = true
                            }

                            advancedOptionButton(
                                title:
                                    ATHLTHLocalization.choose(
                                        english: "Display & input",
                                        norwegian: "Skjerm & registrering"
                                    ),
                                subtitle:
                                    displayControlSummary,
                                icon: "rectangle.and.hand.point.up.left.fill",
                                tint: ATHLTHTheme.accentDeep
                            ) {
                                showingDisplayControls = true
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
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 18)
                .animation(
                    .easeInOut(duration: 0.18),
                    value: trackingMode
                )
            }
            .safeAreaInset(
                edge: .bottom,
                spacing: 0
            ) {
                strengthStickyStartBar
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Start Workout",
                    norwegian: "Start økt"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if let invited = social.takePreparedQuickTrainFriends() {
                    selectedFriendIDs = invited
                }
                if !audioCoachLoaded {
                    audioCoachDraft.load(
                        from: settings
                    )
                    strengthAudioCoach.language =
                        settings.audioCoachLanguage
                    strengthAudioCoach.voiceIdentifier =
                        settings.audioCoachVoiceIdentifier
                    strengthAudioCoach.speechRate =
                        settings.audioCoachSpeechRate
                    strengthAudioCoach.speechVolume =
                        settings.audioCoachSpeechVolume
                    strengthAudioCoach.speechStyle =
                        settings.audioCoachSpeechStyle
                    strengthAudioCoach.duckOtherAudio =
                        settings.audioCoachDuckOtherAudio
                    audioCoachLoaded = true
                }

                if !didLoadSpotifySelection {
                    if session.spotifyAutoplayOnStart == nil,
                       selectedSpotifyPlaylist == nil,
                       let inherited =
                            WorkoutLaunchCoordinator
                                .resolvedSpotifyPlaylist(
                                    workout: session,
                                    session: appSession
                                ) {
                        selectedSpotifyPlaylist =
                            inherited
                        spotifyAutoplay = true
                    } else if
                        session.spotifyAutoplayOnStart == nil,
                        selectedSpotifyPlaylist == nil,
                        let defaultPlaylist =
                            settings.spotifyDefaultPlaylist {
                        selectedSpotifyPlaylist =
                            defaultPlaylist
                        spotifyAutoplay =
                            settings
                                .spotifyAutoplayLinkedPlaylists
                    }
                    didLoadSpotifySelection = true
                }

                if spotify.isConnected &&
                    spotify.playlists.isEmpty {
                    await spotify.refreshPlaylists()
                }

                if social.trainingPartners.isEmpty {
                    await social.refresh()
                }

                await exerciseLibrary.refresh()
            }
            .sheet(
                isPresented: $showingExerciseLibrary
            ) {
                NavigationStack {
                    ExerciseLibraryView(
                        selectionTitle:
                            ATHLTHLocalization.choose(
                                english: "Add to Workout",
                                norwegian: "Legg til i økten"
                            )
                    ) { entry in
                        addExercise(entry.exercise)
                        showingExerciseLibrary = false
                    }
                }
            }
            .sheet(
                isPresented:
                    $showingAIExercisePlanner
            ) {
                StrengthAIExercisePlannerView(
                    existingExercises:
                        configuredExercises,
                    recentWorkouts:
                        strengthWorkout
                            .workoutHistory
                ) {
                    additions in

                    configuredExercises
                        .append(
                            contentsOf:
                                additions
                        )
                }
            }
            .sheet(isPresented: $showingTrainingPlacePicker) {
                ATHLTHPlanTrainingPlacePicker(initial: selectedTrainingPlace) {
                    selectedTrainingPlace = $0
                }
                .environmentObject(appSession)
            }
            .sheet(item: $pendingTreadmillSetup) { exercise in
                PlannedExerciseEditorView(
                    exercise: exercise,
                    advancedMode: trackingMode == .advanced
                ) { updated in
                    configuredExercises.append(updated)
                    pendingTreadmillSetup = nil
                }
            }
            .sheet(item: $exerciseBeingEdited) { exercise in
                PlannedExerciseEditorView(
                    exercise: exercise,
                    advancedMode:
                        trackingMode == .advanced
                ) { updated in
                    if let index =
                        configuredExercises
                            .firstIndex(
                                where: {
                                    $0.id == updated.id
                                }
                            ) {
                        configuredExercises[index] =
                            updated
                    }
                    exerciseBeingEdited = nil
                }
            }
            .sheet(
                isPresented: $showingSpotifyPicker
            ) {
                SpotifyPlaylistPickerView(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Strength Playlist",
                            norwegian: "Spilleliste for styrke"
                        ),
                    selection:
                        $selectedSpotifyPlaylist
                )
                .onDisappear {
                    spotifyAutoplay =
                        selectedSpotifyPlaylist != nil
                }
            }
            .sheet(
                isPresented:
                    $showingAudioCoachSettings
            ) {
                StrengthAudioCoachSettingsView(
                    configuration:
                        $strengthAudioCoach
                )
            }
            .sheet(
                isPresented:
                    $showingRestCueSettings
            ) {
                StrengthRestCueSettingsView(
                    configuration:
                        $restCues
                )
            }
            .sheet(
                isPresented:
                    $showingDisplayControls
            ) {
                StrengthDisplayControlSettingsView(
                    keepScreenAwake:
                        $keepScreenAwake,
                    inputMode:
                        $inputMode,
                    effortMetric:
                        $effortMetric,
                    watchAvailable:
                        appleWatchSelectable &&
                        !ATHLTHDeviceRole.isIPad
                )
            }
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
                    trackingModeButton
                }
            }
        }
    }

    private var strengthStickyStartBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let inlineLaunchError {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.circle")
                        .accessibilityHidden(true)
                    Text(compactWatchStartMessage(inlineLaunchError))
                        .lineLimit(1)
                        .minimumScaleFactor(0.83)
                        .accessibilityLabel(inlineLaunchError)
                    Spacer(minLength: 0)
                    Button { self.inlineLaunchError = nil } label: {
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
                .padding(.horizontal, 18)
                .frame(height: 27)
            }
            if launchInProgress {
                HStack(spacing: 8) {
                    ProgressView().tint(ATHLTHTrainDesign.bronze)
                    Text(ATHLTHLocalization.choose(
                        english: "Starting workout…", norwegian: "Starter treningsøkten…"
                    ))
                    .font(.caption)
                }
                .padding(.horizontal, 18)
            }
            ATHLTHQuickStartDeviceLaunchBar(
                watchAvailable: appleWatchSelectable,
                onIPhone: { startStrength(using: .iPhone) },
                onAppleWatch: { startStrength(using: .appleWatch) },
                preferAppleWatch: watchConnected && !ATHLTHDeviceRole.isIPad,
                supportingText: ATHLTHDeviceRole.isIPad
                    ? ATHLTHLocalization.choose(
                        english: "Starts via your signed-in iPhone.",
                        norwegian: "Startes via din innloggede iPhone."
                    )
                    : nil
            )
            .allowsHitTesting(!launchInProgress)
            .opacity(launchInProgress ? 0.65 : 1)
        }
    }

    private func compactWatchStartMessage(_ message: String) -> String {
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

    private func startStrength(using device: WorkoutCaptureDevice) {
        guard !launchInProgress else { return }
        guard device == .iPhone || appleWatchSelectable else {
            inlineLaunchError = ATHLTHLocalization.choose(
                english: "Apple Watch is not connected. Use iPhone or check the connection.",
                norwegian: "Apple Watch er ikke tilkoblet. Velg iPhone eller kontroller forbindelsen."
            )
            return
        }
        inlineLaunchError = nil
    let selectedFriends = social.resolvedQuickTrainPartners(selectedFriendIDs)

    let advancedConfiguration =
        StrengthAdvancedConfiguration(
            spotifyPlaylist:
                trackingMode == .advanced
                    ? selectedSpotifyPlaylist
                    : nil,
            spotifyAutoplay:
                trackingMode == .advanced &&
                spotifyAutoplay,
            audioCoach:
                strengthAudioCoach,
            restCues:
                restCues,
            keepScreenAwake:
                trackingMode == .advanced &&
                keepScreenAwake,
            inputMode:
                device == .appleWatch
                    ? inputMode
                    : .iPhone,
            effortMetric:
                effortMetric
        )


    var watchAudioCoach =
        strengthAudioCoach.enabled
            ? strengthAudioCoach.watchConfiguration
            : .disabled
    watchAudioCoach
        .strengthHapticsEnabled =
        restCues.hapticsEnabled

    // Wait for Watch confirmation. On failure, retain all selected exercises,
    // weights, settings and this entire sheet instead of navigating home.
    launchInProgress = true
    Task { @MainActor in
        let failure = await onStart(
            configuredSession,
            device,
            trackingMode,
            selectedFriends,
            socialMode,
            watchAudioCoach,
            advancedConfiguration
        )
        launchInProgress = false
        if let failure {
            inlineLaunchError = failure
        } else {
            if trackingMode == .advanced {
                advancedConfiguration.saveAsDefaults()
            }
            dismiss()
        }
    }

    }

    private var spotifySummary: String {
        guard spotifyAutoplay,
              let selectedSpotifyPlaylist
        else {
            return ATHLTHLocalization.choose(
                english: "Off",
                norwegian: "Av"
            )
        }

        return selectedSpotifyPlaylist.name
    }

    private var restCueSummary: String {
        guard restCues.automaticRestTimer else {
            return ATHLTHLocalization.choose(
                english: "Timer off",
                norwegian: "Timer av"
            )
        }

        let hapticText =
            restCues.hapticsEnabled
                ? ATHLTHLocalization.choose(
                    english: "haptics",
                    norwegian: "haptikk"
                )
                : ATHLTHLocalization.choose(
                    english: "no haptics",
                    norwegian: "uten haptikk"
                )

        return "\(restCues.defaultRestSeconds) s · \(hapticText)"
    }

    private var displayControlSummary: String {
        let screen =
            keepScreenAwake
                ? ATHLTHLocalization.choose(
                    english: "Screen on",
                    norwegian: "Skjerm på"
                )
                : ATHLTHLocalization.choose(
                    english: "Auto-lock",
                    norwegian: "Autolås"
                )

        return "\(screen) · \(inputMode.title)"
    }

    private func advancedOptionButton(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(tint)
                    .frame(
                        width: 36,
                        height: 36
                    )
                    .background(
                        tint.opacity(0.10),
                        in: RoundedRectangle(
                            cornerRadius: 11,
                            style: .continuous
                        )
                    )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(title)
                        .font(
                            .subheadline.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 13)
            .frame(height: 58)
            .background(
                Color.white.opacity(0.92),
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
                    Color.black.opacity(0.05),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var configuredSession:
        PlannedSession {
        var configured = session
        configured.exercises = configuredExercises
        configured.plannedTrainingPlace = selectedTrainingPlace
        // A target selected before the workout is preserved for the Watch and
        // the strength log. Measured zones are computed only from actual HR.
        if targetHeartRateZone != session.targetAlertConfiguration?.heartRateZone {
            var alerts = configured.targetAlertConfiguration ??
                WatchWorkoutTargetAlertConfiguration(
                    heartRateEnabled: false,
                    heartRateZone: nil,
                    heartRateMinimumBPM: nil,
                    heartRateMaximumBPM: nil,
                    paceAlertsEnabled: false,
                    paceToleranceSecondsPerKilometer: 15,
                    graceSeconds: 15,
                    repeatSeconds: 120,
                    delivery: .haptic,
                    announceBackInTarget: false
                )
            alerts.heartRateZone = targetHeartRateZone
            alerts.heartRateEnabled = targetHeartRateZone != nil
            configured.targetAlertConfiguration = alerts
        }
        return configured
    }

    private var exerciseSelectionCard:
        some View {
        ATHLTHPlanSurface(density: .compact) {
            HStack(spacing: 8) {
                RoundedRectangle(
                    cornerRadius: 2,
                    style: .continuous
                )
                .fill(
                    ATHLTHTheme
                        .premiumGold
                )
                .frame(
                    width: 4,
                    height: 26
                )

                Text(
                    ATHLTHLocalization.choose(
                        english: "Exercises",
                        norwegian: "Øvelser"
                    )
                )
                .font(
                    .title3.weight(.bold)
                )

                Spacer()

                if !configuredExercises
                    .isEmpty {
                    Text(
                        "\(configuredExercises.count)"
                    )
                    .font(
                        .caption
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .padding(
                        .horizontal,
                        9
                    )
                    .frame(height: 26)
                    .background(
                        Color.primary
                            .opacity(0.05),
                        in: Capsule()
                    )
                }
            }

            if configuredExercises
                .isEmpty {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "No exercises selected yet. Add exercises now, or start freestyle and add them during the workout.",
                        norwegian:
                            "Ingen øvelser er valgt ennå. Legg dem til nå, eller start freestyle og legg dem til under økten."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding(.top, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(
                        Array(
                            configuredExercises
                                .enumerated()
                        ),
                        id: \.element.id
                    ) { index, exercise in
                        HStack(spacing: 10) {
                            Button {
                                exerciseBeingEdited =
                                    exercise
                            } label: {
                                HStack(spacing: 10) {
                                    Text(
                                        "\(index + 1)"
                                    )
                                    .font(
                                        .caption
                                            .bold()
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .accent
                                    )
                                    .frame(
                                        width: 28,
                                        height: 28
                                    )
                                    .background(
                                        ATHLTHTheme
                                            .accentSoft,
                                        in: Circle()
                                    )

                                    VStack(
                                        alignment:
                                            .leading,
                                        spacing: 2
                                    ) {
                                        Text(
                                            exercise
                                                .embeddedExercise
                                                .name
                                        )
                                        .font(
                                            .subheadline
                                                .weight(
                                                    .semibold
                                                )
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .primaryText
                                        )
                                        .lineLimit(1)

                                        Text(
                                            exerciseSummary(
                                                exercise
                                            )
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                    }

                                    Spacer()

                                    Image(
                                        systemName:
                                            "chevron.right"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .tertiary
                                    )
                                }
                                .contentShape(
                                    Rectangle()
                                )
                            }
                            .buttonStyle(.plain)

                            Button(
                                role: .destructive
                            ) {
                                configuredExercises
                                    .remove(
                                        at: index
                                    )
                            } label: {
                                Image(
                                    systemName:
                                        "trash"
                                )
                                .font(
                                    .system(
                                        size: 14,
                                        weight:
                                            .semibold
                                    )
                                )
                                .frame(
                                    width: 34,
                                    height: 34
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(
                            .vertical,
                            2
                        )
                    }
                }
                .padding(.top, 6)
            }

            Button {
                showingExerciseLibrary =
                    true
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Add exercise",
                        norwegian: "Legg til øvelse"
                    ),
                    systemImage:
                        "plus.circle.fill"
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )
                .frame(
                    maxWidth: .infinity
                )
                .frame(height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                ATHLTHTheme.accent
            )
            .background(
                ATHLTHTheme
                    .accentSoft,
                in:
                    RoundedRectangle(
                        cornerRadius: 14,
                        style:
                            .continuous
                    )
            )
            .padding(.top, 8)

            Button {
                showingAIExercisePlanner =
                    true
            } label: {
                HStack(spacing: 9) {
                    Image(
                        systemName:
                            "sparkles"
                    )
                    .font(
                        .system(
                            size: 15,
                            weight:
                                .semibold
                        )
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "AI choose for me",
                            norwegian:
                                "AI velg for meg"
                        )
                    )
                    .font(
                        .subheadline
                            .weight(
                                .semibold
                            )
                    )

                    Spacer()

                    Text("ATHLTH+")
                        .font(
                            .caption2
                                .weight(
                                    .bold
                                )
                        )
                        .padding(
                            .horizontal,
                            7
                        )
                        .frame(height: 23)
                        .background(
                            Color.white
                                .opacity(0.72),
                            in: Capsule()
                        )
                }
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
                .padding(
                    .horizontal,
                    14
                )
                .frame(
                    maxWidth:
                        .infinity
                )
                .frame(height: 46)
                .background(
                    LinearGradient(
                        colors: [
                            ATHLTHTheme
                                .premiumGold
                                .opacity(
                                    0.16
                                ),
                            ATHLTHTheme
                                .vitality
                                .opacity(
                                    0.10
                                )
                        ],
                        startPoint:
                            .leading,
                        endPoint:
                            .trailing
                    ),
                    in:
                        RoundedRectangle(
                            cornerRadius: 14,
                            style:
                                .continuous
                        )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 14,
                        style:
                            .continuous
                    )
                    .stroke(
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.30),
                        lineWidth: 0.8
                    )
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 7)
        }
    }

    private func addExercise(_ exercise: Exercise) {
        let draft = StrengthTreadmillWarmUpDefaults.plannedExercise(
            for: exercise
        )
        if StrengthTreadmillWarmUpDefaults.isTreadmill(exercise.snapshot.name) ||
            StrengthTreadmillWarmUpDefaults.isTreadmill(exercise.snapshot.displayName) {
            // A treadmill warm-up is not silently committed as 3 × 5 min.
            // Confirm (or customize) the one-set, ten-minute suggestion.
            pendingTreadmillSetup = draft
        } else {
            configuredExercises.append(draft)
        }
    }

    private func exerciseSummary(
        _ exercise:
            PlannedExercise
    ) -> String {
        var parts = [
            exercise.compactTargetSummary
        ]

        if let load =
                exercise.compactLoadSummary {
            parts.append(load)
        }

        if let rpe =
            exercise.targetRPE {
            parts.append(
                String(
                    format: "RPE %.1f",
                    rpe
                )
            )
        }

        if let rest =
            exercise.restSeconds {
            parts.append(
                ATHLTHLocalization.format(
                    english: "%d s rest",
                    norwegian: "%d s hvile",
                    rest
                )
            )
        }

        return parts.joined(
            separator: " · "
        )
    }

    private var strengthIntroCard: some View {
        ZStack {
            Image(
                "StrengthQuickHero"
            )
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
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
                Text(session.title)
                    .font(
                        .title2.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        .white
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(
                        0.82
                    )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            trackingMode == .advanced
                                ? "Detailed tracking, exercise by exercise."
                                : "Fast setup. Add exercises here before you start.",
                        norwegian:
                            trackingMode == .advanced
                                ? "Detaljert registrering, øvelse for øvelse."
                                : "Raskt oppsett. Legg til øvelser her før du starter."
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

    private var trackingModeButton: some View {
        Button {
            let nextMode:
                StrengthTrackingMode =
                    trackingMode == .advanced
                        ? .simple
                        : .advanced
            withAnimation(
                .easeInOut(
                    duration: 0.22
                )
            ) {
                trackingMode = nextMode
            }
            settings.recordAdvancedSetup(
                nextMode == .advanced,
                for: .strength
            )
        } label: {
            HStack(spacing: 6) {
                Image(
                    systemName:
                        trackingMode == .advanced
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
                    trackingMode == .advanced
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
                trackingMode == .advanced
                    ? Color.white
                    : ATHLTHTheme.primaryText
            )
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                trackingMode == .advanced
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
                    "Switch strength setup mode",
                norwegian:
                    "Bytt oppsettsmodus for styrke"
            )
        )
    }

    @ViewBuilder
    private func deviceTile(
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
                            size: 20,
                            weight: .semibold
                        )
                    )

                Text(title)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .lineLimit(1)

                Image(
                    systemName:
                        selected
                            ? "checkmark.circle.fill"
                            : "circle"
                )
                .font(.caption)
            }
            .foregroundStyle(
                disabled
                    ? Color.secondary
                    : selected
                        ? Color.white
                        : ATHLTHTheme
                            .primaryText
            )
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(
                disabled
                    ? Color.primary.opacity(0.03)
                    : selected
                        ? ATHLTHTheme.accent
                        : ATHLTHTheme.accentSoft
                            .opacity(0.48),
                in: RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
                .stroke(
                    selected && !disabled
                        ? ATHLTHTheme.accent
                        : Color.primary
                            .opacity(0.06),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.56 : 1)
    }

}

private struct StrengthAudioCoachSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var configuration:
        StrengthAudioCoachConfiguration
    @State private var showDetailedOptions = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        "Audio Coach",
                        isOn: $configuration.enabled
                    )
                }

                Section {
                    HStack(spacing: 7) {
                        ForEach(ATHLTHCoachExperiencePreset.allCases) { preset in
                            Button {
                                applyExperience(preset)
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
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .padding(.horizontal, 5)
                                .foregroundStyle(selectedExperience == preset
                                    ? Color.white : ATHLTHTheme.primaryText)
                                .background(selectedExperience == preset
                                    ? ATHLTHTheme.accentDeep : ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(
                                selectedExperience == preset ? .isSelected : []
                            )
                        }
                    }
                    if selectedExperience == nil {
                        Text(ATHLTHLocalization.choose(
                            english: "Your custom setup is kept until you choose a level.",
                            norwegian: "Ditt tilpassede oppsett beholdes til du velger et nivå."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(ATHLTHLocalization.choose(
                        english: "How much guidance?", norwegian: "Hvor mye veiledning?"
                    ))
                } footer: {
                    Text(ATHLTHLocalization.choose(
                        english: "Speech adapts to sets and rest periods.",
                        norwegian: "Talebeskjeder tilpasses sett og hvile."
                    ))
                }

                Section {
                    HStack(spacing: 9) {
                        ForEach([
                            ATHLTHCoachSpeechStyle.balanced,
                            .motivating
                        ]) { style in
                            Button {
                                configuration.speechStyle = style
                            } label: {
                                Label(style.title, systemImage: style == .motivating
                                    ? "flame.fill" : "waveform")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .foregroundStyle((configuration.speechStyle ?? .balanced) == style
                                        ? Color.white : ATHLTHTheme.primaryText)
                                    .background((configuration.speechStyle ?? .balanced) == style
                                        ? ATHLTHTheme.accentDeep : ATHLTHTheme.accentSoft,
                                        in: RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text(ATHLTHLocalization.choose(
                        english: "Coach personality", norwegian: "Coachen sin talemåte"
                    ))
                }

                Section {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDetailedOptions.toggle()
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
                            Image(systemName: showDetailedOptions
                                ? "chevron.up" : "chevron.down")
                        }
                    }
                }

                if showDetailedOptions {
                Section {
                    Picker(
                        ATHLTHLocalization.choose(
                            english: "Speaking style",
                            norwegian: "Talemåte"
                        ),
                        selection: Binding(
                            get: { configuration.speechStyle ?? .balanced },
                            set: { configuration.speechStyle = $0 }
                        )
                    ) {
                        ForEach(ATHLTHCoachSpeechStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "Changes the wording, not the number of messages or the voice speed.",
                        norwegian: "Endrer ordlyden, ikke antall meldinger eller talehastigheten."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Set completed",
                            norwegian: "Sett fullført"
                        ),
                        isOn:
                            $configuration
                                .announceSetComplete
                    )
                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Rest started",
                            norwegian: "Hvile startet"
                        ),
                        isOn:
                            $configuration
                                .announceRestStarted
                    )
                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Rest countdown",
                            norwegian: "Nedtelling av hvile"
                        ),
                        isOn:
                            $configuration
                                .announceRestCountdown
                    )
                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Rest complete",
                            norwegian: "Hvile ferdig"
                        ),
                        isOn:
                            $configuration
                                .announceRestComplete
                    )
                    Toggle(
                        ATHLTHLocalization.choose(
                            english:
                                "Next exercise + target",
                            norwegian:
                                "Neste øvelse + mål"
                        ),
                        isOn:
                            $configuration
                                .announceNextExercise
                    )
                    Toggle(
                        ATHLTHLocalization.choose(
                            english:
                                "Next set + target",
                            norwegian:
                                "Neste sett + mål"
                        ),
                        isOn:
                            Binding(
                                get: {
                                    configuration
                                        .shouldAnnounceNextSetDetails
                                },
                                set: {
                                    configuration
                                        .announceNextSetDetails =
                                        $0
                                }
                            )
                    )
                    Toggle(
                        ATHLTHLocalization.choose(
                            english:
                                "Exercise progress",
                            norwegian:
                                "Øktfremdrift"
                        ),
                        isOn:
                            Binding(
                                get: {
                                    configuration
                                        .shouldAnnounceExerciseProgress
                                },
                                set: {
                                    configuration
                                        .announceExerciseProgress =
                                        $0
                                }
                            )
                    )
                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Workout status",
                            norwegian: "Øktstatus"
                        ),
                        isOn:
                            $configuration
                                .announceWorkoutStatus
                    )
                } header: {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Announcements",
                            norwegian: "Meldinger"
                        )
                    )
                } footer: {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Next exercise includes its name and first target. Next set can announce reps, load, time or machine level when available. Exercise progress adds where you are in the workout.",
                            norwegian:
                                "Neste øvelse sier navn og første mål. Neste sett kan si reps, vekt, tid eller maskinnivå når det finnes. Øktfremdrift legger til hvor langt du har kommet i økta."
                        )
                    )
                }

                if configuration.announceRestCountdown {
                    Section(
                        ATHLTHLocalization.choose(
                            english: "Rest countdown",
                            norwegian: "Hvilenedtelling"
                        )
                    ) {
                        Stepper(
                            value:
                                $configuration
                                    .restCountdownSeconds,
                            in: 3...30,
                            step: 1
                        ) {
                            Text(
                                ATHLTHLocalization.format(
                                    english: "%d seconds before",
                                    norwegian: "%d sekunder før",
                                    configuration
                                        .restCountdownSeconds
                                )
                            )
                        }
                    }
                }

                if configuration.announceWorkoutStatus {
                    Section(
                        ATHLTHLocalization.choose(
                            english: "Workout status",
                            norwegian: "Øktstatus"
                        )
                    ) {
                        Picker(
                            ATHLTHLocalization.choose(
                                english: "Every",
                                norwegian: "Hvert"
                            ),
                            selection:
                                $configuration
                                    .workoutStatusIntervalMinutes
                        ) {
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                        }
                    }
                }

                Section {
                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Lower music while speaking",
                            norwegian: "Senk musikken mens stemmen snakker"
                        ),
                        isOn:
                            $configuration
                                .duckOtherAudio
                    )
                }
                }
            }
            .navigationTitle("Audio Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Done",
                            norwegian: "Ferdig"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var selectedExperience: ATHLTHCoachExperiencePreset? {
        ATHLTHCoachExperiencePreset.allCases.first { preset in
            let expected = configurationForPreset(preset)
            return configuration.announceSetComplete == expected.announceSetComplete
                && configuration.announceRestStarted == expected.announceRestStarted
                && configuration.announceRestCountdown == expected.announceRestCountdown
                && configuration.announceRestComplete == expected.announceRestComplete
                && configuration.announceNextExercise == expected.announceNextExercise
                && configuration.shouldAnnounceNextSetDetails == expected.shouldAnnounceNextSetDetails
                && configuration.shouldAnnounceExerciseProgress == expected.shouldAnnounceExerciseProgress
                && configuration.announceWorkoutStatus == expected.announceWorkoutStatus
        }
    }

    private func applyExperience(_ preset: ATHLTHCoachExperiencePreset) {
        configuration = configurationForPreset(preset)
    }

    private func configurationForPreset(
        _ preset: ATHLTHCoachExperiencePreset
    ) -> StrengthAudioCoachConfiguration {
        var value = configuration
        value.enabled = true
        value.announceRestComplete = true
        value.announceNextExercise = true
        switch preset {
        case .calm:
            value.announceSetComplete = false
            value.announceRestStarted = false
            value.announceRestCountdown = false
            value.announceNextSetDetails = false
            value.announceExerciseProgress = false
            value.announceWorkoutStatus = false
        case .balanced:
            value.announceSetComplete = true
            value.announceRestStarted = false
            value.announceRestCountdown = true
            value.announceNextSetDetails = true
            value.announceExerciseProgress = false
            value.announceWorkoutStatus = false
        case .active:
            value.announceSetComplete = true
            value.announceRestStarted = true
            value.announceRestCountdown = true
            value.announceNextSetDetails = true
            value.announceExerciseProgress = true
            value.announceWorkoutStatus = true
            value.workoutStatusIntervalMinutes = 15
        }
        return value
    }
}

private struct StrengthRestCueSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var configuration:
        StrengthRestCueConfiguration

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Automatic rest timer",
                            norwegian: "Automatisk hviletimer"
                        ),
                        isOn:
                            $configuration
                                .automaticRestTimer
                    )

                    Stepper(
                        value:
                            $configuration
                                .defaultRestSeconds,
                        in: 0...600,
                        step: 15
                    ) {
                        HStack {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Default rest",
                                    norwegian: "Standard hvile"
                                )
                            )
                            Spacer()
                            Text(
                                "\(configuration.defaultRestSeconds) s"
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(
                        !configuration
                            .automaticRestTimer
                    )

                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Haptic when rest ends",
                            norwegian: "Haptikk når hvilen er ferdig"
                        ),
                        isOn:
                            $configuration
                                .hapticsEnabled
                    )
                }

                Section {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Exercise-specific rest times still take priority. The default is used when an exercise has no rest target.",
                            norwegian:
                                "Hviletid på den enkelte øvelsen har fortsatt prioritet. Standardverdien brukes når øvelsen ikke har egen hviletid."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Rest & Cues",
                    norwegian: "Hvile & varsler"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Done",
                            norwegian: "Ferdig"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct StrengthDisplayControlSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var keepScreenAwake: Bool
    @Binding var inputMode:
        WatchStrengthInputMode
    @Binding var effortMetric:
        StrengthEffortMetric
    let watchAvailable: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Keep iPhone screen awake",
                            norwegian: "Hold iPhone-skjermen aktiv"
                        ),
                        isOn: $keepScreenAwake
                    )
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Set logging",
                        norwegian: "Registrering av sett"
                    )
                ) {
                    Picker(
                        ATHLTHLocalization.choose(
                            english: "Enter reps and weight on",
                            norwegian: "Registrer reps og vekt på"
                        ),
                        selection: $inputMode
                    ) {
                        Text(
                            WatchStrengthInputMode
                                .both.title
                        )
                        .tag(
                            WatchStrengthInputMode
                                .both
                        )

                        Text("iPhone")
                            .tag(
                                WatchStrengthInputMode
                                    .iPhone
                            )

                        if watchAvailable {
                            Text("Apple Watch")
                                .tag(
                                    WatchStrengthInputMode
                                        .appleWatch
                                )
                        }
                    }
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Effort after each set",
                        norwegian: "Anstrengelse etter hvert sett"
                    )
                ) {
                    Picker(
                        ATHLTHLocalization.choose(
                            english: "Effort metric",
                            norwegian: "Anstrengelsesmåling"
                        ),
                        selection:
                            $effortMetric
                    ) {
                        ForEach(
                            StrengthEffortMetric.allCases
                        ) { metric in
                            Text(metric.title)
                                .tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "RPE rates overall effort from 1–10. RIR records how many repetitions you felt you had left. Off keeps set logging faster.",
                            norwegian:
                                "RPE angir total anstrengelse fra 1–10. RIR registrerer hvor mange repetisjoner du følte du hadde igjen. Av gjør settregistreringen raskere."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Both keeps iPhone and Apple Watch synchronized. Choosing one device makes the other a read-only workout companion.",
                            norwegian:
                                "Begge holder iPhone og Apple Watch synkronisert. Velger du én enhet blir den andre en skrivebeskyttet treningspartner."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Display & Input",
                    norwegian: "Skjerm & registrering"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Done",
                            norwegian: "Ferdig"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
        }
    }
}

