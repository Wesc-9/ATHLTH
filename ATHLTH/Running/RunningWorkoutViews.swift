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

    var body: some View {
        VStack(spacing: 0) {
            if source == nil {
                Picker("Workout source", selection: $selectedSection) {
                    ForEach(RunningWorkoutLibrarySection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
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
                    Text(workout.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

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
    @AppStorage("athlth.workoutPreview.advanced.v1") private var advancedMode = false

    let workout: RunningWorkoutTemplate
    let selectionTitle: String?
    let onSelect: ((RunningWorkoutTemplate) -> Void)?
    let onStart: ((RunningWorkoutTemplate) -> Void)?

    @State private var showingDelete = false
    @State private var showingIntervalEditor = false
    @State private var editingBeforeStart = false
    @State private var askingForTargets = false
    @State private var pendingAddToPlan = false
    @State private var lastHistory: ATHLTHLibraryWorkoutHistory.Summary?

    private func refreshLastHistory() {
        let records = ATHLTHRunningPerformanceHistory.load(
            userID: session.profile.userID
        )
        lastHistory = ATHLTHLibraryWorkoutHistory.running(
            id: workout.id, records: records
        )
    }

    private var personalCopy: RunningWorkoutTemplate? {
        library.savedCopy(for: workout)
    }

    /// A catalogue page always shows the catalogue original. Personalized
    /// copies appear only when opening that specific workout in My Workouts.
    private var previewWorkout: RunningWorkoutTemplate {
        workout.isBuiltIn
            ? ATHLTHRunningLibraryDefaults.unpersonalized(workout)
            : workout
    }

    private func continueWithSavedCopy() {
        if let saved = personalCopy {
            onSelect?(saved)
        } else if workout.isBuiltIn {
            let copy = library.duplicate(workout)
            onSelect?(copy)
        } else {
            onSelect?(workout)
        }
        dismiss()
    }

    private func handleFirstAddition(toPlan: Bool) {
        pendingAddToPlan = toPlan
        if workout.isBuiltIn &&
            ATHLTHWorkoutFirstUsePolicy.asksForTargets(
                advanced: advancedMode, hasPersonalCopy: personalCopy != nil
            ) {
            askingForTargets = true
        } else if toPlan {
            continueWithSavedCopy()
        } else if personalCopy == nil && workout.isBuiltIn {
            _ = library.duplicate(workout)
        }
    }

    private func editPersonalizedCopy() {
        editingBeforeStart = false
        showingIntervalEditor = true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ATHLTHWorkoutRecipePreview(
                    title: previewWorkout.title,
                    summary: previewWorkout.summary,
                    category: "running",
                    symbol: previewWorkout.type.systemImage,
                    difficulty: nil,
                    durationMinutes: previewWorkout.estimatedDurationSeconds.map {
                        Int(($0 / 60).rounded(.up))
                    },
                    blocks: previewWorkout.recipePreviewBlocks
                )

                ATHLTHLastWorkoutHistoryCard(summary: lastHistory)

                if let onStart {
                    Button {
                        editingBeforeStart = true
                        showingIntervalEditor = true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Adjust workout before starting",
                                norwegian: "Tilpass økten før start"
                            ),
                            systemImage: "slider.horizontal.3"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(ATHLTHPlanDesign.accentInk)

                    Button {
                        onStart(previewWorkout)
                        dismiss()
                    } label: {
                        Label("Start Workout", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ATHLTHPlanDesign.accentInk)
                }

                Button {
                        editPersonalizedCopy()
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
                        handleFirstAddition(toPlan: false)
                    } label: {
                        Label(
                            personalCopy == nil
                                ? ATHLTHLocalization.choose(
                                    english: "Save in My Workouts",
                                    norwegian: "Lagre i Mine økter"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Saved in My Workouts",
                                    norwegian: "Lagret i Mine økter"
                                ),
                            systemImage: personalCopy == nil ? "doc.on.doc" : "checkmark.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(personalCopy != nil)
                } else {
                    Button("Delete Workout", role: .destructive) {
                        showingDelete = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .navigationTitle(ATHLTHLocalization.choose(english: "Running workout", norwegian: "Løpeøkt"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let onSelect {
                VStack(spacing: 0) {
                    Divider()
                        .opacity(0.35)

                    Button {
                        handleFirstAddition(toPlan: true)
                    } label: {
                        Label(
                            selectionTitle ?? "Use Workout",
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
                english: "Add your pace and other personal targets?",
                norwegian: "Vil du legge inn fart og andre personlige mål?"
            ),
            isPresented: $askingForTargets,
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Enter targets in Advanced", norwegian: "Legg inn mål i Avansert"
            )) {
                editPersonalizedCopy()
            }
            Button(ATHLTHLocalization.choose(
                english: "Use workout without personal targets",
                norwegian: "Bruk økten uten personlige mål"
            )) {
                if pendingAddToPlan {
                    continueWithSavedCopy()
                } else if personalCopy == nil {
                    _ = library.duplicate(workout)
                }
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel", norwegian: "Avbryt"
            ), role: .cancel) {}
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "The workout structure stays as it is. Pace, incline and personal zones are optional and you can add them later.",
                norwegian: "Øktoppsettet beholdes. Fart, stigning og egne pulssoner er valgfrie og kan legges inn senere."
            ))
        }
        .sheet(isPresented: $showingIntervalEditor) {
            ATHLTHTrainIntervalComposerView(initial: previewWorkout) { edited in
                var personalized = edited
                personalized.sharedSourceWorkoutID = edited.sharedSourceWorkoutID ??
                    (workout.isBuiltIn ? workout.id : workout.sharedSourceWorkoutID)
                // A pace or incline entered before a run is personal, too.
                // Persist it so the next library visit can restore those settings.
                library.save(personalized)
                if editingBeforeStart, let onStart {
                    onStart(personalized)
                } else if pendingAddToPlan {
                    onSelect?(personalized)
                }
                dismiss()
            }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Title", text: $title)

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
                        library.save(
                            RunningWorkoutTemplate(
                                id: UUID(),
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                type: type,
                                summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                                blocks: blocks,
                                routeID: nil,
                                isBuiltIn: false,
                                createdAt: Date(),
                                updatedAt: Date()
                            )
                        )
                        dismiss()
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        blocks.isEmpty
                    )
                }
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
