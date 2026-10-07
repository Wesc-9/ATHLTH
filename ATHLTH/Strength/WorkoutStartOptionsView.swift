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
    ) -> Void

    @State private var captureDevice: WorkoutCaptureDevice
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

    @State private var showingSpotifyPicker = false
    @State private var didLoadSpotifySelection = false
    @State private var showingAudioCoachSettings = false
    @State private var showingRestCueSettings = false
    @State private var showingTrainingPartners = false
    @State private var showingDisplayControls = false

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
        ) -> Void
    ) {
        self.session = session
        self.trainingDeviceProvider = trainingDeviceProvider
        self.watchConnected = watchConnected
        self.onStart = onStart

        // Workout capture is chosen for this workout only.
        // A workout started from iPhone stays on iPhone unless the user
        // explicitly chooses Apple Watch in this sheet.
        let initialDevice: WorkoutCaptureDevice =
            .iPhone

        let savedAdvanced =
            StrengthAdvancedConfiguration
                .savedDefaults()

        _captureDevice = State(initialValue: initialDevice)
        _trackingMode = State(
            initialValue: defaultTracking == .advanced ? .advanced : .simple
        )
        _configuredExercises = State(
            initialValue: session.exercises
        )
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
        _strengthAudioCoach = State(
            initialValue:
                savedAdvanced.audioCoach
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

    private var workoutDeviceCaption: String {
        if ATHLTHDeviceRole.isIPad {
            return ATHLTHLocalization.choose(
                english:
                    "iPad sends the start request to your signed-in iPhone. Apple Watch starts through the paired iPhone.",
                norwegian:
                    "iPad sender startforespørselen til iPhonen du er logget inn på. Apple Watch startes via den parede iPhonen."
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "This choice applies only to this workout.",
            norwegian:
                "Valget gjelder bare denne økten."
        )
    }

    private var startButtonTitle: String {
        if ATHLTHDeviceRole.isIPad {
            return captureDevice == .appleWatch
                ? ATHLTHLocalization.choose(
                    english:
                        "Start Apple Watch via iPhone",
                    norwegian:
                        "Start Apple Watch via iPhone"
                )
                : ATHLTHLocalization.choose(
                    english: "Start on iPhone",
                    norwegian: "Start på iPhone"
                )
        }

        return captureDevice == .appleWatch
            ? ATHLTHLocalization.choose(
                english:
                    "Start with Apple Watch",
                norwegian:
                    "Start med Apple Watch"
            )
            : ATHLTHLocalization.choose(
                english: "Start on iPhone",
                norwegian: "Start på iPhone"
            )
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

                    ATHLTHCard {
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
                                    english:
                                        "Workout device",
                                    norwegian:
                                        "Treningsenhet"
                                )
                            )
                            .font(
                                .title3.weight(
                                    .bold
                                )
                            )

                            Spacer()
                        }

                        HStack(spacing: 10) {
                            deviceTile(
                                title: "iPhone",
                                icon: "iphone",
                                selected:
                                    captureDevice == .iPhone,
                                disabled: false
                            ) {
                                captureDevice = .iPhone
                            }

                            deviceTile(
                                title: "Apple Watch",
                                icon: "applewatch",
                                selected:
                                    captureDevice == .appleWatch,
                                disabled: !appleWatchSelectable
                            ) {
                                captureDevice =
                                    .appleWatch
                            }
                        }
                        .padding(.top, 10)

                        Text(
                            workoutDeviceCaption
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    }

                    advancedOptionButton(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Train with someone",
                                norwegian:
                                    "Trene med noen"
                            ),
                        subtitle:
                            selectedFriendIDs.isEmpty
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "Private invite · optional",
                                    norwegian:
                                        "Privat invitasjon · valgfritt"
                                )
                                : ATHLTHLocalization.format(
                                    english:
                                        "%d selected · %@",
                                    norwegian:
                                        "%d valgt · %@",
                                    selectedFriendIDs.count,
                                    socialMode.title
                                ),
                        icon: "person.2.fill",
                        tint: ATHLTHTheme.vitality
                    ) {
                        showingTrainingPartners = true
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
                                title: "Audio Coach",
                                subtitle:
                                    strengthAudioCoach.enabled
                                        ? ATHLTHLocalization.choose(
                                            english: "Strength cues on",
                                            norwegian: "Styrkevarsler på"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english: "Off",
                                            norwegian: "Av"
                                        ),
                                icon: "waveform.and.mic",
                                tint: ATHLTHTheme.premiumGold
                            ) {
                                showingAudioCoachSettings = true
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
                    $showingTrainingPartners
            ) {
                NavigationStack {
                    ScrollView {
                        ATHLTHCard {
                            VStack(
                                alignment:
                                    .leading,
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
                        .padding(16)
                    }
                    .navigationTitle(
                        ATHLTHLocalization.choose(
                            english:
                                "Train with someone",
                            norwegian:
                                "Trene med noen"
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
                                showingTrainingPartners = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
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
                        captureDevice == .appleWatch &&
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
        strengthStartButton
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

    private var strengthStartButton: some View {
        Button {
            let selectedFriends =
                social.trainingPartners
                    .filter {
                        selectedFriendIDs
                            .contains(
                                $0.userID
                            )
                    }

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
                        captureDevice == .appleWatch
                            ? inputMode
                            : .iPhone,
                    effortMetric:
                        effortMetric
                )

            if trackingMode == .advanced {
                advancedConfiguration
                    .saveAsDefaults()
            }

            var watchAudioCoach =
                trackingMode == .advanced
                    ? strengthAudioCoach
                        .watchConfiguration
                    : .disabled
            watchAudioCoach
                .strengthHapticsEnabled =
                restCues.hapticsEnabled

            onStart(
                configuredSession,
                captureDevice,
                trackingMode,
                selectedFriends,
                socialMode,
                watchAudioCoach,
                advancedConfiguration
            )
            dismiss()
        } label: {
            Label(
                startButtonTitle,
                systemImage:
                    captureDevice ==
                    .appleWatch
                        ? "applewatch"
                        : "play.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(ATHLTHTheme.vitality)
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
        configured.exercises =
            configuredExercises
        return configured
    }

    private var exerciseSelectionCard:
        some View {
        ATHLTHCard {
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

    private func addExercise(
        _ exercise: Exercise
    ) {
        configuredExercises.append(
            PlannedExercise(
                id: UUID(),
                exerciseID:
                    exercise.id,
                embeddedExercise:
                    exercise.snapshot,
                sets: 3,
                reps: 8,
                targetWeightKilograms:
                    nil,
                targetRPE: nil,
                restSeconds: 90,
                notes: nil,
                targetRIR: nil,
                supersetGroupID: nil,
                progression:
                    StrengthProgressionRule
                        .none
            )
        )
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

