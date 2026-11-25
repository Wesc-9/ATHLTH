import SwiftUI

enum RunningWorkoutLibrarySection: String, CaseIterable, Identifiable {
    case library
    case mine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .mine: return "My Workouts"
        }
    }
}

struct RunningWorkoutLibraryView: View {
    @EnvironmentObject private var library: RunningWorkoutLibraryStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var recents: LibraryRecentsStore
    @EnvironmentObject private var session: AppSessionStore
    @State private var lastRuns: [ATHLTHCompletedRunningPerformance] = []

    private func refreshRunHistory() {
        lastRuns = ATHLTHRunningPerformanceHistory.load(userID: session.profile.userID)
    }

    let source: RunningWorkoutLibrarySection?
    let selectionTitle: String?
    let onSelect: ((RunningWorkoutTemplate) -> Void)?
    let onStart: ((RunningWorkoutTemplate) -> Void)?

    @State private var query = ""
    @State private var selectedType: RunningWorkoutType?
    @State private var favoritesOnly = false
    @State private var showingBuilder = false
    @State private var confirmingLegacyRestore = false
    @State private var selectedSection: RunningWorkoutLibrarySection = .library

    init(
        source: RunningWorkoutLibrarySection? = nil,
        selectionTitle: String? = nil,
        onSelect: ((RunningWorkoutTemplate) -> Void)? = nil,
        onStart: ((RunningWorkoutTemplate) -> Void)? = nil
    ) {
        self.source = source
        _selectedSection = State(initialValue: source ?? .library)
        self.selectionTitle = selectionTitle
        self.onSelect = onSelect
        self.onStart = onStart
    }

    private var templates: [RunningWorkoutTemplate] {
        let sourceTemplates = library.allTemplates.filter { workout in
            switch selectedSection {
            case .library:
                return workout.isBuiltIn
            case .mine:
                return !workout.isBuiltIn
            }
        }

        let typeFiltered: [RunningWorkoutTemplate]
        if let selectedType {
            typeFiltered = sourceTemplates.filter { $0.type == selectedType }
        } else {
            typeFiltered = sourceTemplates
        }

        let favoriteFiltered =
            favoritesOnly
                ? typeFiltered.filter {
                    favorites.isFavorite(
                        .workout,
                        itemID: $0.id.uuidString
                    )
                }
                : typeFiltered

        return favoriteFiltered.filter {
            ATHLTHWorkoutSearch.matches(
                query, texts: [$0.title, $0.summary, $0.type.title]
            )
        }
    }

    private var sectionIndex: Binding<Int> {
        Binding(
            get: {
                RunningWorkoutLibrarySection.allCases.firstIndex(
                    of: selectedSection
                ) ?? 0
            },
            set: { index in
                guard RunningWorkoutLibrarySection.allCases.indices.contains(index) else {
                    return
                }
                selectedSection = RunningWorkoutLibrarySection.allCases[index]
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if source == nil {
                ATHLTHLibraryGlossyTabRow(
                    titles: RunningWorkoutLibrarySection.allCases.map(\.title),
                    selection: sectionIndex,
                    identifiers: RunningWorkoutLibrarySection.allCases.map {
                        "running-workout-library-source-\($0.rawValue)"
                    }
                )
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        favoritesOnly.toggle()
                    } label: {
                        typeChip(
                            "Favorites",
                            selected: favoritesOnly
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedType = nil
                    } label: {
                        typeChip("All", selected: selectedType == nil)
                    }
                    .buttonStyle(.plain)

                    ForEach(RunningWorkoutType.allCases) { type in
                        Button {
                            selectedType = type
                        } label: {
                            typeChip(
                                type.title,
                                selected: selectedType == type
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            if selectedSection == .mine && library.hasUnassignedLegacyWorkouts {
                Button("Restore older workouts from this device") {
                    confirmingLegacyRestore = true
                }
                .padding()
            }

            if templates.isEmpty && selectedSection == .mine && selectedType == nil {
                ContentUnavailableView {
                    Label("No custom workouts yet", systemImage: "figure.run")
                } description: {
                    Text("Build your own running workout and it will appear here.")
                } actions: {
                    Button("Build Workout") {
                        showingBuilder = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if templates.isEmpty {
                ContentUnavailableView(
                    "No workouts",
                    systemImage: "figure.run",
                    description: Text("Try another workout type.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(templates) { workout in
                            ZStack(alignment: .topTrailing) {
                                NavigationLink {
                                    RunningWorkoutDetailView(
                                        workout: workout,
                                        selectionTitle: selectionTitle,
                                        onSelect: onSelect,
                                        onStart: onStart
                                    )
                                } label: {
                                    workoutCard(workout)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        recents.markUsed(
                                            .workout,
                                            itemID: workout.id.uuidString,
                                            title: workout.title,
                                            subtitle: workout.type.title,
                                            icon: workout.type.systemImage
                                        )
                                    }
                                )

                                LibraryFavoriteButton(
                                    kind: .workout,
                                    itemID: workout.id.uuidString,
                                    title: workout.title,
                                    subtitle: workout.type.title,
                                    icon: workout.type.systemImage
                                )
                                .padding(9)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .confirmationDialog("Restore workouts to this account?", isPresented: $confirmingLegacyRestore, titleVisibility: .visible) {
            Button("These are my workouts — restore") {
                library.restoreUnassignedDeviceWorkouts()
            }
        } message: {
            Text("Older workouts on this device have no account identifier. Only restore them if they belong to you.")
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(selectionTitle ?? "Running Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshRunHistory)
        .onReceive(NotificationCenter.default.publisher(for: .athlthTrainingDataDidChange)) { _ in
            refreshRunHistory()
        }
        .task {
            recents.refresh()
            await favorites.refresh()
        }
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search running workouts"
        )
        .toolbar {
            if selectedSection == .mine {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingBuilder = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Build running workout")
                }
            }
        }
        .sheet(isPresented: $showingBuilder) {
            ATHLTHTrainIntervalComposerView { template in
                library.save(template)
                selectedSection = .mine
            }
            .environmentObject(library)
        }
    }

    private func typeChip(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(selected ? .white : ATHLTHPlanDesign.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                selected ? ATHLTHPlanDesign.accentInk : ATHLTHPlanDesign.selectedSurface,
                in: Capsule()
            )
    }

    private func workoutCard(_ workout: RunningWorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: workout.type.systemImage)
                    .font(.title2)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: 44, height: 44)
                    .background(ATHLTHPlanDesign.selectedSurface, in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLibraryName.workoutCard(workout.title, grid: false))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .accessibilityLabel(workout.title)

                    Text(workout.type.title)
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }

                Spacer()

                if !workout.isBuiltIn {
                    Text("MY WORKOUT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ATHLTHTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(ATHLTHTheme.accent.opacity(0.10), in: Capsule())
                }
            }

            Text(workout.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

            if let last = ATHLTHLibraryWorkoutHistory.running(
                id: workout.id, records: lastRuns
            ) {
                ATHLTHLastWorkoutHistoryLabel(summary: last)
            }

            HStack(spacing: 10) {
                Label(
                    ATHLTHLocalization.counted(
                            workout.blocks.count,
                            englishSingular: "block",
                            englishPlural: "blocks",
                            norwegianSingular: "blokk",
                            norwegianPlural: "blokker"
                        ),
                    systemImage: "list.number"
                )

                if let distance = workout.estimatedDistanceMeters {
                    Label(
                        String(format: "%.1f km", distance / 1_000),
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }

                if let duration = workout.estimatedDurationSeconds {
                    Label(
                        ATHLTHLocalization.format(
                            english: "%d min",
                            norwegian: "%d min",
                            Int((duration / 60).rounded())
                        ),
                        systemImage: "timer"
                    )
                }

                Spacer()

                Image(systemName: "chevron.right")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .athlthPlanCard(radius: 20)
    }
}

struct RunningWorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: RunningWorkoutLibraryStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @AppStorage("athlth.workoutPreview.advanced.v1") private var advancedMode = false

    let workout: RunningWorkoutTemplate
    let selectionTitle: String?
    let onSelect: ((RunningWorkoutTemplate) -> Void)?
    let onStart: ((RunningWorkoutTemplate) -> Void)?

    @State private var showingDelete = false
    @State private var copySaveError: String?
    @State private var showingIntervalEditor = false
    @State private var focusedPrivateStepIndex: Int?
    @State private var showingOneTimeSettings = false
    @State private var oneTimeStartRequested = false
    @State private var showingOneTimeComposer = false
    @State private var showingOneTimeCoach = false
    @State private var showingOneTimeSpotify = false
    @State private var oneTimeWorkout: RunningWorkoutTemplate?
    @State private var oneTimeOptions = ATHLTHWorkoutPersonalOptions()
    @State private var oneTimeCoachDraft = AudioCoachDraft()
    @State private var oneTimeSongStep: PrivateSongStep?
    @State private var editingPrivatePreset = false
    @State private var showingPrivateStartChoices = false
    @State private var showingPrivateCoach = false
    @State private var showingPrivateSpotify = false
    @State private var showingResetPrivateSettings = false
    @State private var privateSavedWorkout: RunningWorkoutTemplate?
    @State private var privateOptions = ATHLTHWorkoutPersonalOptions()
    @State private var privateCoachDraft = AudioCoachDraft()
    @State private var selectedPrivateSongStep: PrivateSongStep?
    private struct PrivateSongStep: Identifiable {
        let index: Int
        var id: Int { index }
    }
    @State private var lastHistory: ATHLTHLibraryWorkoutHistory.Summary?
    @State private var importEnvironment: RunEnvironment = .outdoor
    @State private var didResolveImportEnvironment = false
    @State private var importAdjustedWorkout: RunningWorkoutTemplate?

    private func refreshLastHistory() {
        let records = ATHLTHRunningPerformanceHistory.load(
            userID: session.profile.userID
        )
        lastHistory = ATHLTHLibraryWorkoutHistory.running(
            id: workout.id, records: records
        )
    }

    private var hasSavedPrivateSettings: Bool {
        privateSavedWorkout != nil ||
        privateOptions != ATHLTHWorkoutPersonalOptions()
    }

    private func reloadPrivateSettings() {
        guard workout.isBuiltIn else { return }
        privateSavedWorkout = ATHLTHRunningPrivateWorkoutStore.load(
            userID: session.profile.userID, source: workout
        )
        privateOptions = ATHLTHWorkoutPersonalOptionsStore.load(
            userID: session.profile.userID.uuidString,
            workoutID: workout.id
        )
    }

    private func savePrivateWorkout(_ edited: RunningWorkoutTemplate) {
        guard ATHLTHRunningPrivateWorkoutStore.save(
            userID: session.profile.userID, source: workout,
            customized: edited
        ) else {
            copySaveError = ATHLTHLocalization.choose(
                english: "Could not save your private settings.",
                norwegian: "Kunne ikke lagre dine private innstillinger."
            )
            return
        }
        reloadPrivateSettings()
        editingPrivatePreset = false
    }

    private func resetPrivateSettings() {
        ATHLTHRunningPrivateWorkoutStore.reset(
            userID: session.profile.userID, sourceID: workout.id
        )
        ATHLTHWorkoutPersonalOptionsStore.reset(
            userID: session.profile.userID.uuidString,
            workoutID: workout.id
        )
        privateSavedWorkout = nil
        privateOptions = .init()
    }

    /// Only the chosen running plan is passed to Quick Train. Private audio
    /// and song choices are memory-only launch fields excluded from Codable.
    private func launchLibraryWorkout(
        _ selected: RunningWorkoutTemplate,
        with options: ATHLTHWorkoutPersonalOptions
    ) {
        var payload = selected
        payload.launchAudioCoachConfiguration = options.audioCoachConfiguration
        payload.launchSpotifyPlaylist = options.spotifyPlaylist
        payload.launchSpotifyAutoplayOnStart = options.spotifyAutoplayOnStart
        payload.launchSpotifyIntervalTrack = options.spotifyIntervalTrack
        payload.launchStepSongs = options.stepSongs.isEmpty
            ? nil : options.stepSongs
        onStart?(payload)
        dismiss()
    }

    private func applyPrivateSpeed(_ speed: Double) {
        let candidate = ATHLTHRunningPrivateSpeedPolicy.applying(
            kilometersPerHour: speed,
            to: privateSavedWorkout ?? ATHLTHRunningLibraryDefaults.unpersonalized(workout)
        )
        savePrivateWorkout(candidate)
    }

    private func openPrivateCoach() {
        var draft = AudioCoachDraft()
        draft.load(configuration: privateOptions.audioCoachConfiguration ??
            settings.audioCoachConfiguration(
                enabled: settings.audioCoachEnabledByDefault
            ))
        privateCoachDraft = draft
        showingPrivateCoach = true
    }

    /// A catalogue page always shows the catalogue original. Personalized
    /// copies appear only when opening that specific workout in My Workouts.
    private var previewWorkout: RunningWorkoutTemplate {
        let source = workout.isBuiltIn
            ? (privateSavedWorkout ?? ATHLTHRunningLibraryDefaults.unpersonalized(workout))
            : workout
        guard onSelect != nil else { return source }
        var selected = importAdjustedWorkout ?? source
        selected.launchRunEnvironment = importEnvironment
        selected.routeID = importEnvironment == .outdoor ? source.routeID : nil
        return selected
    }

    private var importModePicker: some View {
        Menu {
            Picker(ATHLTHLocalization.choose(english: "Detail level", norwegian: "Detaljnivå"), selection: $advancedMode) {
                Text(ATHLTHLocalization.choose(english: "Simple", norwegian: "Enkel")).tag(false)
                Text(ATHLTHLocalization.choose(english: "Advanced", norwegian: "Avansert")).tag(true)
            }
        } label: {
            HStack(spacing: 4) {
                Text(advancedMode
                    ? ATHLTHLocalization.choose(english: "Advanced", norwegian: "Avansert")
                    : ATHLTHLocalization.choose(english: "Simple", norwegian: "Enkel"))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(ATHLTHPlanDesign.accentInk)
            .padding(.horizontal, 11)
            .frame(minHeight: 36)
            .background(ATHLTHPlanDesign.selectedSurface, in: Capsule())
        }
        .accessibilityIdentifier("workout-recipe-detail-mode")
    }

    private var importPace: Double? {
        let efforts = previewWorkout.blocks.filter { $0.kind == .work }.flatMap { block in
            (1...min(max(block.repetitions, 1), 60)).map { block.resolvedWork(at: $0).intensity.paceMinSecondsPerKilometer }
        }
        guard let first = efforts.first ?? nil, efforts.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private var importHero: some View {
        let selected = previewWorkout
        let steps = selected.recipePreviewBlocks
        return VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Image(systemName: selected.type.systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: 44, height: 44)
                    .background(ATHLTHPlanDesign.selectedSurface, in: RoundedRectangle(cornerRadius: 14))
                Text(ATHLTHLocalization.choose(english: "RUNNING", norwegian: "LØPING"))
                    .font(.caption2.weight(.bold)).tracking(2)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Spacer(minLength: 0)
            }
            Text(selected.title)
                .font(.system(size: 31, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !selected.summary.isEmpty {
                Text(selected.summary)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(ATHLTHPlanDesign.outline.opacity(0.5))
            HStack(alignment: .top, spacing: 7) {
                importMetric("\(steps.count)", ATHLTHLocalization.choose(english: "Steps", norwegian: "Deler"), icon: "square.stack")
                Divider()
                importMetric(ATHLTHLocalization.choose(english: "All levels", norwegian: "Alle nivåer"), ATHLTHLocalization.choose(english: "Level", norwegian: "Nivå"), icon: "chart.bar.xaxis")
                Divider()
                importMetric(selected.estimatedDurationSeconds.map { "~\(Int(($0 / 60).rounded(.up))) min" } ?? "—", ATHLTHLocalization.choose(english: "Duration", norwegian: "Varighet"), icon: "clock")
            }
            .fixedSize(horizontal: false, vertical: true)
            if let meters = selected.estimatedDistanceMeters {
                Label(ATHLTHLocalization.choose(english: "Estimated distance", norwegian: "Estimert distanse") + " · " + String(format: "%.2f km", meters / 1000), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            if onSelect != nil {
                Divider().overlay(ATHLTHPlanDesign.outline.opacity(0.5))
                Text(ATHLTHLocalization.choose(english: "Running environment", norwegian: "Løpemiljø"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                Picker(ATHLTHLocalization.choose(english: "Running environment", norwegian: "Løpemiljø"), selection: $importEnvironment) {
                    Text(ATHLTHLocalization.choose(english: "Outdoor", norwegian: "Utendørs")).tag(RunEnvironment.outdoor)
                    Text(ATHLTHLocalization.choose(english: "Indoor", norwegian: "Innendørs")).tag(RunEnvironment.indoor)
                    Text(ATHLTHLocalization.choose(english: "Treadmill", norwegian: "Tredemølle")).tag(RunEnvironment.treadmill)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("athlth-running-import-environment")
                let count = ATHLTHRunningPrivateSpeedPolicy.workCount(in: selected)
                if count > 0 {
                    ATHLTHRunningPrivateSpeedEditor(effortCount: count, environment: importEnvironment, currentPace: importPace) { speed in
                        applyImportSpeed(speed)
                    }
                }
            }
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [ATHLTHPlanDesign.surface, ATHLTHPlanDesign.selectedSurface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.8) }
        .accessibilityIdentifier("athlth-running-import-hero")
    }

    private func importMetric(_ value: String, _ label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            Text(value).font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .lineLimit(2).minimumScaleFactor(0.8)
            Text(label).font(.caption2).foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func continueWithSavedCopy() {
        // Choosing the original for a plan never silently creates or
        // switches to a personal copy. Mine is selected explicitly elsewhere.
        onSelect?(previewWorkout)
        dismiss()
    }

    private func applyImportSpeed(_ speed: Double) {
        // Remember personal pace on the original built-in recipe, never create
        // a new library workout and never persist the temporary import venue.
        var adjusted = ATHLTHRunningPrivateSpeedPolicy.applying(kilometersPerHour: speed, to: previewWorkout)
        adjusted.launchRunEnvironment = nil
        adjusted.routeID = (privateSavedWorkout ?? workout).routeID
        importAdjustedWorkout = adjusted
        if workout.isBuiltIn, session.signedIn, !session.previewModeEnabled {
            savePrivateWorkout(adjusted)
        }
    }

    private func editPersonalizedCopy() {
        editingPrivatePreset = false
        focusedPrivateStepIndex = nil
        showingIntervalEditor = true
    }

    private func editPrivatePreset(focusing index: Int? = nil) {
        editingPrivatePreset = true
        focusedPrivateStepIndex = index
        showingIntervalEditor = true
    }

    private func beginOneTimeAdjustment() {
        oneTimeStartRequested = false
        oneTimeWorkout = previewWorkout
        oneTimeOptions = privateOptions
        showingOneTimeSettings = true
    }

    private func openOneTimeCoach() {
        var draft = AudioCoachDraft()
        draft.load(configuration: oneTimeOptions.audioCoachConfiguration ??
            settings.audioCoachConfiguration(
                enabled: settings.audioCoachEnabledByDefault
            ))
        oneTimeCoachDraft = draft
        showingOneTimeCoach = true
    }

    /// Deliberately isolated from the long workout timeline: no recompute
    /// on every keystroke, Spotify lookup or audio-engine state update.
    private var privateRunningSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    ATHLTHLocalization.choose(
                        english: "My private settings",
                        norwegian: "Mine innstillinger"
                    ), systemImage: "person.crop.circle"
                )
                .font(.headline)
                Spacer()
                Text(ATHLTHLocalization.choose(
                    english: "Only visible to you", norwegian: "Kun synlig for deg"
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }

            let count = ATHLTHRunningPrivateSpeedPolicy.workCount(
                in: previewWorkout
            )
            if count > 0 {
                ATHLTHRunningPrivateSpeedEditor(effortCount: count) {
                    applyPrivateSpeed($0)
                }
            }

            Button {
                editPrivatePreset()
            } label: {
                Label("Rediger og lagre alle øktdeler",
                      systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            Divider()
            Button(action: openPrivateCoach) {
                Label("Audio Coach", systemImage: "waveform")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            Button { showingPrivateSpotify = true } label: {
                Label("Spotify", systemImage: "music.note")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }

            DisclosureGroup("Sang per drag eller pause") {
                let steps = previewWorkout.recipePreviewBlocks
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(steps.indices, id: \.self) { index in
                        Button {
                            selectedPrivateSongStep = PrivateSongStep(
                                index: index
                            )
                        } label: {
                            HStack {
                                Text(steps[index].title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(privateOptions.stepSongs[index]?.title ??
                                     "Velg sang")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(ATHLTHPlanDesign.ink)

            if hasSavedPrivateSettings {
                Button(role: .destructive) {
                    showingResetPrivateSettings = true
                } label: {
                    Label("Nullstill mine innstillinger",
                          systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(ATHLTHPlanDesign.ink)
        .padding(16)
        .athlthPlanCard(radius: 20)
        .accessibilityIdentifier("athlth-running-private-options")
    }

    private var oneTimeSettingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text(ATHLTHLocalization.choose(
                        english: "Changes here apply only to this run.",
                        norwegian: "Endringene gjelder bare denne økten og lagres ikke i Mine innstillinger."
                    ))
                    .font(.footnote)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                    if let selected = oneTimeWorkout {
                        Button { showingOneTimeComposer = true } label: {
                            HStack {
                                Label("Rediger alle drag og pauser",
                                      systemImage: "slider.horizontal.3")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .padding(15)
                        .athlthPlanCard(radius: 18)

                        if ATHLTHRunningPrivateSpeedPolicy.workCount(in: selected) > 0 {
                            ATHLTHRunningPrivateSpeedEditor(
                                effortCount: ATHLTHRunningPrivateSpeedPolicy
                                    .workCount(in: selected)
                            ) { speed in
                                oneTimeWorkout = ATHLTHRunningPrivateSpeedPolicy.applying(
                                    kilometersPerHour: speed, to: selected
                                )
                            }
                            .padding(13)
                            .athlthPlanCard(radius: 18)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Audio og musikk").font(.headline)
                            Button(action: openOneTimeCoach) {
                                Label("Audio Coach", systemImage: "waveform")
                                    .frame(maxWidth: .infinity, minHeight: 44,
                                           alignment: .leading)
                            }
                            Button { showingOneTimeSpotify = true } label: {
                                Label("Spotify", systemImage: "music.note")
                                    .frame(maxWidth: .infinity, minHeight: 44,
                                           alignment: .leading)
                            }
                            DisclosureGroup("Sang per drag og pause") {
                                let steps = selected.recipePreviewBlocks
                                LazyVStack(alignment: .leading, spacing: 5) {
                                    ForEach(steps.indices, id: \.self) { index in
                                        Button {
                                            oneTimeSongStep = PrivateSongStep(index: index)
                                        } label: {
                                            HStack {
                                                Text(steps[index].title)
                                                    .lineLimit(1)
                                                Spacer(minLength: 8)
                                                Text(oneTimeOptions.stepSongs[index]?.title ??
                                                     "Velg sang")
                                                    .font(.caption)
                                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                                    .lineLimit(1)
                                                Image(systemName: "chevron.right")
                                            }
                                            .frame(minHeight: 40)
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .padding(15)
                        .athlthPlanCard(radius: 18)

                        Button {
                            // Dismiss the editor first; the original Quick
                            // Run flow is opened after the sheet is gone.
                            oneTimeStartRequested = true
                            showingOneTimeSettings = false
                        } label: {
                            Label("Start med disse innstillingene",
                                  systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHPlanDesign.accentInk)
                    }
                }
                .padding(16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle("Juster denne gangen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { showingOneTimeSettings = false }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $showingOneTimeComposer) {
            ATHLTHTrainIntervalComposerView(initial: oneTimeWorkout) { edited in
                oneTimeWorkout = edited
            }
        }
        .sheet(isPresented: $showingOneTimeCoach) {
            NavigationStack {
                ScrollView {
                    PerWorkoutAudioCoachView(
                        draft: $oneTimeCoachDraft,
                        showRouteOptions: oneTimeWorkout?.routeID != nil,
                        showStructuredOptions: true
                    )
                    .padding(16)
                }
                .navigationTitle("Audio Coach")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Avbryt") { showingOneTimeCoach = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Bruk") {
                            oneTimeOptions.audioCoachConfiguration =
                                oneTimeCoachDraft.configuration()
                            showingOneTimeCoach = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingOneTimeSpotify) {
            ATHLTHWorkoutSpotifyOptionsSheet(
                playlist: $oneTimeOptions.spotifyPlaylist,
                autoplay: $oneTimeOptions.spotifyAutoplayOnStart,
                intervalTrack: $oneTimeOptions.spotifyIntervalTrack,
                supportsIntervals: true
            )
        }
        .sheet(item: $oneTimeSongStep) { selection in
            ATHLTHSpotifyIntervalTrackPicker(selection: Binding(
                get: { oneTimeOptions.stepSongs[selection.index] },
                set: { track in
                    if let track {
                        oneTimeOptions.stepSongs[selection.index] = track
                    } else {
                        oneTimeOptions.stepSongs.removeValue(forKey: selection.index)
                    }
                }
            ))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                importHero
                ATHLTHWorkoutRecipePreview(
                    title: previewWorkout.title,
                    summary: previewWorkout.summary,
                    category: "running",
                    symbol: previewWorkout.type.systemImage,
                    difficulty: nil,
                    durationMinutes: previewWorkout.estimatedDurationSeconds.map {
                        Int(($0 / 60).rounded(.up))
                    },
                    blocks: previewWorkout.recipePreviewBlocks,
                    compactDetailLayout: true,
                    detailAdvancedMode: $advancedMode,
                    showEstimatedDistance: false,
                    configuredMaximumOnly: true,
                    onEditStep: onSelect == nil ? { index in
                        if workout.isBuiltIn {
                            editPrivatePreset(focusing: index)
                        } else {
                            editPersonalizedCopy()
                        }
                    } : nil
                )

                if workout.isBuiltIn && onSelect == nil {
                    privateRunningSettingsCard
                }

                ATHLTHLastWorkoutHistoryCard(summary: lastHistory)

                if let onStart {
                    Button {
                        showingPrivateStartChoices = true
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Start workout", norwegian: "Start økt"
                        ), systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ATHLTHPlanDesign.accentInk)
                }

                if onSelect == nil {
                Button {
                        if workout.isBuiltIn {
                            editPrivatePreset()
                        } else {
                            editPersonalizedCopy()
                        }
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Edit detailed workout", norwegian: "Rediger detaljert økt"
                            ),
                            systemImage: "slider.horizontal.3"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHPlanDesign.accentInk)

                if workout.isBuiltIn {
                    Button {
                        editPersonalizedCopy()
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Customize and save a new workout",
                                norwegian: "Tilpass og lagre ny variant"
                            ),
                            systemImage: "square.and.pencil"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Delete Workout", role: .destructive) {
                        showingDelete = true
                    }
                    .frame(maxWidth: .infinity)
                }
                }
            }
            .padding()
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .navigationTitle(ATHLTHLocalization.choose(english: "Running workout", norwegian: "Løpeøkt"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { importModePicker }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let onSelect {
                VStack(spacing: 0) {
                    Divider()
                        .opacity(0.35)

                    Button {
                        continueWithSavedCopy()
                    } label: {
                        Label(
                            selectionTitle == nil || selectionTitle == "Choose Workout" || selectionTitle == "Use Workout"
                                ? ATHLTHLocalization.choose(english: "Choose workout", norwegian: "Velg økt")
                                : selectionTitle ?? "",
                            systemImage: "plus.circle.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ATHLTHPlanDesign.accentInk)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                }
                .background(.ultraThinMaterial)
            }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Which settings would you like to use?",
                norwegian: "Hvilke innstillinger vil du bruke?"
            ),
            isPresented: $showingPrivateStartChoices,
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "No personal settings", norwegian: "Ingen innstillinger"
            )) {
                launchLibraryWorkout(
                    ATHLTHRunningLibraryDefaults.unpersonalized(workout),
                    with: .init()
                )
            }
            Button(ATHLTHLocalization.choose(
                english: "My settings", norwegian: "Mine innstillinger"
            )) {
                launchLibraryWorkout(previewWorkout, with: privateOptions)
            }
            .disabled(!hasSavedPrivateSettings)
            Button(ATHLTHLocalization.choose(
                english: "Adjust now", norwegian: "Juster nå"
            )) {
                beginOneTimeAdjustment()
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel", norwegian: "Avbryt"
            ), role: .cancel) {}
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Saved settings are private. Adjust now changes only this start.",
                norwegian: "Lagrede innstillinger er private. Juster nå endrer bare denne starten."
            ))
        }
        .sheet(isPresented: $showingIntervalEditor) {
            ATHLTHTrainIntervalComposerView(
                initial: previewWorkout,
                focusedTimelineStepIndex: focusedPrivateStepIndex
            ) { edited in
                var personalized = edited
                personalized.sharedSourceWorkoutID = edited.sharedSourceWorkoutID ??
                    (workout.isBuiltIn ? workout.id : workout.sharedSourceWorkoutID)
                // Starting an edited original does not automatically save a
                // personal copy. Explicit library copies must be changed and
                // renamed; rejected saves keep the original intact.
                if editingPrivatePreset {
                    savePrivateWorkout(personalized)
                } else if library.save(personalized) {
                    dismiss()
                } else {
                    let original = workout.isBuiltIn
                        ? workout
                        : (RunningWorkoutLibraryStore.builtInTemplates.first {
                            $0.id == personalized.sharedSourceWorkoutID
                          } ?? workout)
                    copySaveError =
                        ATHLTHRunningWorkoutCopyPolicy.saveError(
                            personalized, comparedTo: original
                        ) ?? ATHLTHLocalization.choose(
                            english: "Could not save this copy.",
                            norwegian: "Kunne ikke lagre kopien."
                        )
                }
            }
        }
        .sheet(
            isPresented: $showingOneTimeSettings,
            onDismiss: {
                guard oneTimeStartRequested, let selected = oneTimeWorkout
                else { return }
                oneTimeStartRequested = false
                launchLibraryWorkout(selected, with: oneTimeOptions)
            }
        ) {
            oneTimeSettingsSheet
        }
        .onAppear {
            reloadPrivateSettings()
            if !didResolveImportEnvironment {
                let source = privateSavedWorkout ?? workout
                if let environment = source.launchRunEnvironment {
                    importEnvironment = environment
                } else if source.routeID == nil && source.blocks.contains(where: { block in
                    block.work.treadmillInclinePercent != nil ||
                        block.recovery?.treadmillInclinePercent != nil ||
                        (block.repetitionOverrides ?? []).contains {
                            $0.work?.treadmillInclinePercent != nil || $0.recovery?.treadmillInclinePercent != nil
                        }
                }) {
                    importEnvironment = .treadmill
                }
                didResolveImportEnvironment = true
            }
            refreshLastHistory()
        }
        .onChange(of: session.profile.userID) { _, _ in
            importAdjustedWorkout = nil
            reloadPrivateSettings()
            refreshLastHistory()
        }
        .onChange(of: privateOptions) { _, updated in
            guard workout.isBuiltIn else { return }
            ATHLTHWorkoutPersonalOptionsStore.save(
                updated, userID: session.profile.userID.uuidString,
                workoutID: workout.id
            )
        }
        .sheet(isPresented: $showingPrivateCoach) {
            NavigationStack {
                ScrollView {
                    PerWorkoutAudioCoachView(
                        draft: $privateCoachDraft,
                        showRouteOptions: workout.routeID != nil,
                        showStructuredOptions: true
                    )
                    .padding(16)
                }
                .navigationTitle("Audio Coach")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Avbryt") { showingPrivateCoach = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Lagre") {
                            privateOptions.audioCoachConfiguration =
                                privateCoachDraft.configuration()
                            showingPrivateCoach = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingPrivateSpotify) {
            ATHLTHWorkoutSpotifyOptionsSheet(
                playlist: $privateOptions.spotifyPlaylist,
                autoplay: $privateOptions.spotifyAutoplayOnStart,
                intervalTrack: $privateOptions.spotifyIntervalTrack,
                supportsIntervals: true
            )
        }
        .sheet(item: $selectedPrivateSongStep) { chosen in
            ATHLTHSpotifyIntervalTrackPicker(selection: Binding(
                get: { privateOptions.stepSongs[chosen.index] },
                set: { song in
                    if let song {
                        privateOptions.stepSongs[chosen.index] = song
                    } else {
                        privateOptions.stepSongs.removeValue(forKey: chosen.index)
                    }
                }
            ))
        }
        .confirmationDialog(
            "Nullstille mine innstillinger?",
            isPresented: $showingResetPrivateSettings,
            titleVisibility: .visible
        ) {
            Button("Nullstill", role: .destructive) {
                resetPrivateSettings()
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Personlig fart, Audio Coach og Spotify fjernes. Originaløkten beholdes.")
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Copy not saved", norwegian: "Kopien ble ikke lagret"
            ),
            isPresented: Binding(
                get: { copySaveError != nil },
                set: { if !$0 { copySaveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(copySaveError ?? "")
        }
        .onAppear(perform: refreshLastHistory)
        .onReceive(NotificationCenter.default.publisher(for: .athlthTrainingDataDidChange)) { _ in
            refreshLastHistory()
        }
        .confirmationDialog(
            "Delete this running workout?",
            isPresented: $showingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                library.delete(workout.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct RunningWorkoutBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: RunningWorkoutLibraryStore

    @State private var title = "My Running Workout"
    @State private var type: RunningWorkoutType = .custom
    @State private var summary = ""
    @State private var blocks: [RunningWorkoutBlock] = []
    @State private var showingBlockEditor = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField(
                        ATHLTHLocalization.choose(english: "Title", norwegian: "Navn"),
                        text: $title
                    )
                    .onChange(of: title) { _, updated in
                        if updated.count > ATHLTHLibraryName.maximumWorkoutCharacters {
                            title = String(updated.prefix(ATHLTHLibraryName.maximumWorkoutCharacters))
                        }
                    }

                    Picker("Type", selection: $type) {
                        ForEach(RunningWorkoutType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }

                    TextField(
                        "Description",
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }

                Section("Structure") {
                    if blocks.isEmpty {
                        Text("Add a block for warm-up, steady running, intervals, recovery or cool-down.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                            RunningWorkoutBlockRow(
                                index: index + 1,
                                block: block
                            )
                            .swipeActions {
                                Button(role: .destructive) {
                                    blocks.removeAll { $0.id == block.id }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onMove { offsets, destination in
                            blocks.move(
                                fromOffsets: offsets,
                                toOffset: destination
                            )
                        }
                    }

                    Button {
                        showingBlockEditor = true
                    } label: {
                        Label("Add Block", systemImage: "plus.circle.fill")
                    }
                }

                Section {
                    Text("A block can repeat work + recovery several times. This structure is ready for wearable workout guidance as supported providers are connected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Build Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let item = RunningWorkoutTemplate(
                            id: UUID(),
                            title: String(title.trimmingCharacters(in: .whitespacesAndNewlines)
                                .prefix(ATHLTHLibraryName.maximumWorkoutCharacters)),
                            type: type,
                            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                            blocks: blocks,
                            routeID: nil,
                            isBuiltIn: false,
                            createdAt: Date(),
                            updatedAt: Date()
                        )
                        if library.save(item) {
                            dismiss()
                        } else {
                            saveError = ATHLTHLocalization.choose(
                                english: "Choose a different name from the original workout.",
                                norwegian: "Velg et annet navn enn originaløkten."
                            )
                        }
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        blocks.isEmpty
                    )
                }
            }
            .alert(
                ATHLTHLocalization.choose(
                    english: "Workout not saved", norwegian: "Økten ble ikke lagret"
                ),
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            .sheet(isPresented: $showingBlockEditor) {
                RunningBlockEditorView { block in
                    blocks.append(block)
                }
            }
        }
    }
}

struct RunningBlockEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (RunningWorkoutBlock) -> Void

    @State private var kind: RunningBlockKind = .work
    @State private var title = "Work"
    @State private var repetitions = 1

    @State private var measure: RunningMeasureKind = .distance
    @State private var distanceMeters = 1_000.0
    @State private var durationMinutes = 5.0

    @State private var intensityKind: RunningIntensityKind = .rpe
    @State private var rpe = 7.0
    @State private var heartRateZone = 3
    @State private var paceMinutes = 5
    @State private var paceSeconds = 0

    @State private var recoveryEnabled = false
    @State private var recoveryMeasure: RunningMeasureKind = .time
    @State private var recoveryMeters = 200.0
    @State private var recoverySeconds = 90.0

    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Block") {
                    Picker("Phase", selection: $kind) {
                        ForEach(RunningBlockKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }

                    TextField("Title", text: $title)

                    if kind == .work {
                        Stepper(
                            "Repeats: \(repetitions)",
                            value: $repetitions,
                            in: 1...50
                        )
                    }
                }

                Section("Work") {
                    Picker("Measure", selection: $measure) {
                        ForEach(RunningMeasureKind.allCases) { measure in
                            Text(measure.title).tag(measure)
                        }
                    }
                    .pickerStyle(.segmented)

                    if measure == .distance {
                        HStack {
                            Text("Distance")
                            Spacer()
                            TextField(
                                "1000",
                                value: $distanceMeters,
                                format: .number.precision(.fractionLength(0))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            Text("m")
                                .foregroundStyle(.secondary)
                        }
                    } else if measure == .time {
                        HStack {
                            Text("Duration")
                            Spacer()
                            TextField(
                                "5",
                                value: $durationMinutes,
                                format: .number.precision(.fractionLength(0...1))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            Text("min")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Intensity") {
                    Picker("Target", selection: $intensityKind) {
                        ForEach(RunningIntensityKind.allCases) { intensity in
                            Text(intensity.title).tag(intensity)
                        }
                    }

                    if intensityKind == .rpe {
                        HStack {
                            Text("RPE")
                            Slider(value: $rpe, in: 1...10, step: 0.5)
                            Text("\(rpe, specifier: "%.1f")")
                                .monospacedDigit()
                        }
                    } else if intensityKind == .heartRateZone {
                        Stepper(
                            "Heart-rate zone: \(heartRateZone)",
                            value: $heartRateZone,
                            in: 1...5
                        )
                    } else if intensityKind == .pace {
                        Stepper(
                            "Pace minutes: \(paceMinutes)",
                            value: $paceMinutes,
                            in: 2...15
                        )
                        Stepper(
                            "Pace seconds: \(paceSeconds)",
                            value: $paceSeconds,
                            in: 0...55,
                            step: 5
                        )
                    }
                }

                if kind == .work && repetitions > 1 {
                    Section("Recovery between reps") {
                        Toggle(
                            "Add recovery",
                            isOn: $recoveryEnabled
                        )

                        if recoveryEnabled {
                            Picker(
                                "Measure",
                                selection: $recoveryMeasure
                            ) {
                                Text("Time").tag(RunningMeasureKind.time)
                                Text("Distance").tag(RunningMeasureKind.distance)
                            }
                            .pickerStyle(.segmented)

                            if recoveryMeasure == .time {
                                Stepper(
                                    "Recovery: \(Int(recoverySeconds)) sec",
                                    value: $recoverySeconds,
                                    in: 15...900,
                                    step: 15
                                )
                            } else {
                                Stepper(
                                    "Recovery: \(Int(recoveryMeters)) m",
                                    value: $recoveryMeters,
                                    in: 50...2_000,
                                    step: 50
                                )
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField(
                        "Optional cues",
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }
            }
            .navigationTitle("Add Running Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(makeBlock())
                        dismiss()
                    }
                }
            }
            .onChange(of: kind) { _, kind in
                if title == "Work" || title.isEmpty {
                    title = kind.title
                }

                if kind != .work {
                    repetitions = 1
                }
            }
        }
    }

    private func makeBlock() -> RunningWorkoutBlock {
        let target: RunningStepTarget

        switch measure {
        case .distance:
            target = .distance(
                max(distanceMeters, 1),
                intensity: intensityTarget
            )
        case .time:
            target = .time(
                max(durationMinutes, 0.1) * 60,
                intensity: intensityTarget
            )
        case .open:
            target = RunningStepTarget(
                measure: .open,
                distanceMeters: nil,
                durationSeconds: nil,
                intensity: intensityTarget
            )
        }

        let recovery: RunningStepTarget?
        if recoveryEnabled && repetitions > 1 {
            if recoveryMeasure == .distance {
                recovery = .distance(
                    max(recoveryMeters, 1),
                    intensity: .easy
                )
            } else {
                recovery = .time(
                    max(recoverySeconds, 1),
                    intensity: .easy
                )
            }
        } else {
            recovery = nil
        }

        return RunningWorkoutBlock(
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? kind.title
                : title.trimmingCharacters(in: .whitespacesAndNewlines),
            repetitions: max(repetitions, 1),
            work: target,
            recovery: recovery,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var intensityTarget: RunningIntensityTarget {
        switch intensityKind {
        case .none:
            return .none
        case .easy:
            return .easy
        case .pace:
            let pace = Double(paceMinutes * 60 + paceSeconds)
            return RunningIntensityTarget(
                kind: .pace,
                paceMinSecondsPerKilometer: pace,
                paceMaxSecondsPerKilometer: pace,
                heartRateZone: nil,
                rpe: nil
            )
        case .heartRateZone:
            return RunningIntensityTarget(
                kind: .heartRateZone,
                paceMinSecondsPerKilometer: nil,
                paceMaxSecondsPerKilometer: nil,
                heartRateZone: heartRateZone,
                rpe: nil
            )
        case .rpe:
            return RunningIntensityTarget(
                kind: .rpe,
                paceMinSecondsPerKilometer: nil,
                paceMaxSecondsPerKilometer: nil,
                heartRateZone: nil,
                rpe: rpe
            )
        }
    }
}

struct RunningWorkoutBlockRow: View {
    let index: Int
    let block: RunningWorkoutBlock

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.caption.bold())
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 28, height: 28)
                .background(ATHLTHTheme.accent.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(block.title)
                        .font(.subheadline.weight(.semibold))

                    if block.repetitions > 1 {
                        Text("× \(block.repetitions)")
                            .font(.caption.bold())
                            .foregroundStyle(ATHLTHTheme.accent)
                    }
                }

                Text(stepDescription(block.work))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let recovery = block.recovery {
                    Text(ATHLTHLocalization.format(
                                english: "Recovery · %@",
                                norwegian: "Restitusjon · %@",
                                stepDescription(recovery)
                            ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let notes = block.notes {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: phaseIcon(block.kind))
                .foregroundStyle(ATHLTHTheme.accent)
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func stepDescription(_ step: RunningStepTarget) -> String {
        var pieces: [String] = []

        switch step.measure {
        case .distance:
            if let meters = step.distanceMeters {
                if meters >= 1_000 {
                    pieces.append(
                        String(format: "%.2g km", meters / 1_000)
                    )
                } else {
                    pieces.append("\(Int(meters.rounded())) m")
                }
            }
        case .time:
            if let duration = step.durationSeconds {
                if duration >= 60 {
                    pieces.append(
                        String(format: "%.0f min", duration / 60)
                    )
                } else {
                    pieces.append("\(Int(duration.rounded())) sec")
                }
            }
        case .open:
            pieces.append("Open")
        }

        switch step.intensity.kind {
        case .none:
            break
        case .easy:
            pieces.append("Easy")
        case .pace:
            if let pace = step.intensity.paceMinSecondsPerKilometer {
                pieces.append("\(paceString(pace))/km")
            }
        case .heartRateZone:
            if let zone = step.intensity.heartRateZone {
                pieces.append("HR Z\(zone)")
            }
        case .rpe:
            if let rpe = step.intensity.rpe {
                pieces.append(String(format: "RPE %.1f", rpe))
            }
        }

        return pieces.joined(separator: " · ")
    }

    private func paceString(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func phaseIcon(_ kind: RunningBlockKind) -> String {
        switch kind {
        case .warmup: return "flame"
        case .work: return "bolt.fill"
        case .recovery: return "arrow.counterclockwise"
        case .steady: return "figure.run"
        case .cooldown: return "snowflake"
        }
    }
}
