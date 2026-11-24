import SwiftUI

/// One browser for full main-section exercises: public curated prescriptions
/// and private sections captured from the athlete's own saved workouts.
struct ATHLTHCompoundExerciseLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @ObservedObject private var catalog = WorkoutTemplateCatalogStore.shared

    var runningOnly = false
    var insertionPhase: WorkoutPhaseKind = .main
    var onSelect: (([WorkoutTemplateBlock]) -> Void)? = nil

    @State private var records: [ATHLTHCompoundExercise] = []
    @State private var savedSectionIDs: Set<UUID> = []
    @State private var query = ""
    @State private var selectedCategory: ATHLTHCompoundExercise.Category? = .intervals
    @State private var selection = 0

    private var displayed: [ATHLTHCompoundExercise] {
        let favoriteIDs = Set(favorites.favorites.lazy
            .filter { $0.itemType == .exercise }.map(\.itemID))
        return records.filter { entry in
            (!runningOnly || entry.isRunning) &&
            (selectedCategory == nil || entry.category == selectedCategory) &&
            (selection == 0 && !entry.isPersonal ||
             selection == 1 && entry.isPersonal ||
             selection == 2 && favoriteIDs.contains(entry.id)) &&
            (query.isEmpty ||
             entry.title.localizedStandardContains(query) ||
             entry.category.title.localizedStandardContains(query) ||
             entry.detail.localizedStandardContains(query))
        }
    }

    private var categories: [ATHLTHCompoundExercise.Category] {
        if runningOnly {
            return [.intervals, .threshold, .hills, .fartlek, .running]
        }
        return ATHLTHCompoundExercise.Category.allCases
    }

    private func refresh() {
        let mySections = ATHLTHWorkoutMainSectionLibrary.load(
            userID: session.profile.userID
        )
        savedSectionIDs = Set(mySections.map(\.id))
        // Build once on source revisions rather than hashing every exercise
        // on each search keystroke and SwiftUI view publication.
        records = ATHLTHCompoundExerciseCatalog.build(
            running: runningLibrary.allTemplates,
            workoutCatalog: catalog.entries,
            saved: mySections
        )
    }

    private func removeSavedSection(_ item: ATHLTHCompoundExercise) {
        let owned = item.sourceIDs.filter(savedSectionIDs.contains)
        for id in owned {
            // This only removes cached main-section entries. It never
            // deletes the original workout or the athlete's recordings.
            ATHLTHWorkoutMainSectionLibrary.delete(
                id, userID: session.profile.userID
            )
        }
        refresh()
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(ATHLTHLocalization.choose(
                english: "Source", norwegian: "Kilde"
            ), selection: $selection) {
                Text(ATHLTHLocalization.choose(english: "Public", norwegian: "Offentlig")).tag(0)
                Text(ATHLTHLocalization.choose(english: "Mine", norwegian: "Mine")).tag(1)
                Text(ATHLTHLocalization.choose(english: "Favorites", norwegian: "Favoritter")).tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .accessibilityIdentifier("compound-exercises-source-tabs")

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(
                    ATHLTHLocalization.choose(
                        english: "Search workouts and interval exercises",
                        norwegian: "Søk etter intervaller og hoveddeler"
                    ),
                    text: $query
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
            .padding(12)
            .background(ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(nil, ATHLTHLocalization.choose(
                        english: "All", norwegian: "Alle"
                    ))
                    ForEach(categories) { category in
                        categoryChip(category, category.title)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 11)

            if displayed.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(
                        english: "No matching main exercises",
                        norwegian: "Ingen passende hovedøvelser"
                    ),
                    systemImage: "figure.run",
                    description: Text(ATHLTHLocalization.choose(
                        english: "Try another category, or save a training session to keep its main section privately.",
                        norwegian: "Prøv en annen kategori, eller lagre en treningsøkt for å beholde hoveddelen privat."
                    ))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(displayed) { item in
                            NavigationLink {
                                ATHLTHCompoundExerciseDetailView(
                                    exercise: item,
                                    insertionPhase: insertionPhase,
                                    onSelect: onSelect
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.category == .strength
                                        ? "dumbbell" : "figure.run")
                                        .font(.title3.weight(.medium))
                                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                        .frame(width: 46, height: 46)
                                        .background(ATHLTHPlanDesign.selectedSurface,
                                                    in: RoundedRectangle(cornerRadius: 13))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(ATHLTHPlanDesign.ink)
                                            .multilineTextAlignment(.leading)
                                        Text(item.category.title + " · " + item.detail)
                                            .font(.caption)
                                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                }
                                .padding(13)
                                .athlthPlanCard(radius: 17)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if item.isPersonal &&
                                    item.sourceIDs.contains(where: savedSectionIDs.contains) {
                                    Button(role: .destructive) {
                                        removeSavedSection(item)
                                    } label: {
                                        Label(ATHLTHLocalization.choose(
                                            english: "Remove saved main section",
                                            norwegian: "Fjern lagret hoveddel"
                                        ), systemImage: "trash")
                                    }
                                }
                            }
                            .accessibilityIdentifier("compound-exercise-" + item.id)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Running and main exercises", norwegian: "Løping og hovedøvelser"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onChange(of: catalog.entries) { _, _ in refresh() }
        .onReceive(runningLibrary.$customTemplates) { _ in refresh() }
        .onChange(of: session.profile.userID) { _, _ in refresh() }
        .task { await catalog.refresh() }
    }

    private func categoryChip(
        _ category: ATHLTHCompoundExercise.Category?, _ title: String
    ) -> some View {
        Button { selectedCategory = category } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selectedCategory == category
                    ? Color.white : ATHLTHPlanDesign.ink)
                .padding(.horizontal, 13)
                .frame(minHeight: 35)
                .background(selectedCategory == category
                    ? ATHLTHPlanDesign.ink : ATHLTHPlanDesign.selectedSurface,
                    in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Full prescription before insertion: no warm-up/cool-down duplication.
struct ATHLTHCompoundExerciseDetailView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.dismiss) private var dismiss

    let exercise: ATHLTHCompoundExercise
    var insertionPhase: WorkoutPhaseKind = .main
    var onSelect: (([WorkoutTemplateBlock]) -> Void)? = nil

    @State private var completedHistory: [ATHLTHCompletedRunningPerformance] = []

    private func reloadHistory() {
        completedHistory = ATHLTHRunningPerformanceHistory.load(userID: session.profile.userID)
    }

    private var measuredIntervalResults: [ATHLTHCompoundExerciseProgress.Result] {
        guard exercise.isRunning else { return [] }
        return ATHLTHCompoundExerciseProgress.results(
            for: exercise,
            completed: completedHistory
        )
    }

    /// Show the exercise's intended effort zones, never the easy recovery
    /// as its primary intensity. Legacy 4×4 recipes get protocol guidance.
    private var exerciseZoneText: String? {
        let efforts = exercise.blocks.filter {
            $0.kind == .run && !$0.isRestOrActiveRecovery
        }
        let range = ATHLTHPlannedWorkoutMetrics.plannedHeartRateZoneRange(
            for: efforts.isEmpty ? exercise.blocks : efforts
        )
        let prefix = ATHLTHLocalization.isNorwegian ? "S" : "Z"
        if let range {
            return range.lowerBound == range.upperBound
                ? "\(prefix)\(range.lowerBound)"
                : "\(prefix)\(range.lowerBound)–\(prefix)\(range.upperBound)"
        }
        return exercise.familyID == "athlth:running:interval:4x4"
            ? "\(prefix)4–\(prefix)5" : nil
    }

    private var fourByFourResults: [ATHLTHFourByFourRecords.Result] {
        guard exercise.familyID == "athlth:running:interval:4x4",
              let recovery = ATHLTHCompoundExerciseCatalog.fourByFourRecovery(
                exercise.blocks
              )
        else { return [] }
        return ATHLTHFourByFourRecords.records(
            completedHistory
        ).filter { $0.recoverySeconds == recovery }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                // Reuse the same premium workout identity card as the
                // planned-session editor instead of an unframed text header.
                ATHLTHWorkoutDetailsCard(
                    activityTitle: exercise.title,
                    symbol: exercise.isRunning ? "figure.run" : "dumbbell",
                    showsTimingLabel: false
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Label(exercise.category.title,
                                  systemImage: "square.stack.3d.up")
                            if let exerciseZoneText {
                                Label(exerciseZoneText, systemImage: "heart")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        Text(exercise.detail)
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("athlth-compound-exercise-hero")

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.number")
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                        Text(ATHLTHLocalization.choose(
                            english: "Main section", norwegian: "Hoveddel"
                        ))
                        .font(.headline.weight(.semibold))
                    }
                    ForEach(Array(exercise.blocks.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 11) {
                            Image(systemName: step.isRestOrActiveRecovery
                                  ? "pause.fill" : step.kind.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ATHLTHTrainDesign.bronze)
                                .frame(width: 38, height: 38)
                                .background(ATHLTHPlanDesign.surface,
                                            in: RoundedRectangle(cornerRadius: 11))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                Text(stepSummary(step))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                            Spacer(minLength: 4)
                            Text("\(index + 1)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ATHLTHPlanDesign.selectedSurface.opacity(0.45),
                                    in: RoundedRectangle(cornerRadius: 13))
                    }
                }
                .padding(15)
                .athlthPlanCard(radius: 20)

                if exercise.familyID == "athlth:running:interval:4x4" {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ATHLTHLocalization.choose(
                            english: "My 4×4 results", norwegian: "Mine 4×4-resultater"
                        ))
                        .font(.headline)
                        if let best = fourByFourResults.first {
                            Text(String(format: "%.1f km/t", best.averageSpeedKmh))
                                .font(.title2.weight(.semibold))
                            Text(ATHLTHLocalization.choose(
                                english: "Best comparable work-effort speed · \(fourByFourResults.count) completed",
                                norwegian: "Beste sammenlignbare dragfart · \(fourByFourResults.count) fullførte"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        } else {
                            Text(ATHLTHLocalization.choose(
                                english: "No completed, comparable 4×4 attempts recorded yet.",
                                norwegian: "Ingen registrerte, sammenlignbare 4×4-forsøk ennå."
                            ))
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    .padding(16)
                    .athlthPlanCard(radius: 19)
                }
                if exercise.isRunning {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ATHLTHLocalization.choose(
                            english: "My interval exercise history",
                            norwegian: "Min intervallhistorikk"
                        ))
                        .font(.headline)
                        if let best = ATHLTHCompoundExerciseProgress.bestMeasured(
                            measuredIntervalResults
                        ) {
                            Text(String(format: "%.1f km/t", best.averageWorkSpeedKmh))
                                .font(.title2.weight(.semibold))
                            Text(ATHLTHLocalization.choose(
                                english: "Best recorded effort speed",
                                norwegian: "Beste målte dragfart"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        if let reported = ATHLTHCompoundExerciseProgress.bestReported(
                            measuredIntervalResults
                        ) {
                            Text(ATHLTHLocalization.choose(
                                english: "Reported treadmill result",
                                norwegian: "Oppgitt mølleresultat"
                            ) + " · " + String(
                                format: "%.1f km/t", reported.averageWorkSpeedKmh
                            ))
                            .font(.caption)
                        }
                        if !measuredIntervalResults.isEmpty {
                            Divider()
                            Text(ATHLTHLocalization.choose(english: "Latest attempts", norwegian: "Siste gjennomføringer"))
                                .font(.subheadline.weight(.semibold))
                            ForEach(Array(measuredIntervalResults.prefix(5))) { result in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.subheadline.weight(.medium))
                                        Text(result.reported
                                             ? ATHLTHLocalization.choose(english: "Reported", norwegian: "Manuelt oppgitt")
                                             : result.source)
                                            .font(.caption2)
                                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    }
                                    Spacer()
                                    Text(String(format: "%.1f km/t", result.averageWorkSpeedKmh))
                                        .font(.subheadline.monospacedDigit())
                                }
                            }
                        }
                        Text(ATHLTHLocalization.choose(
                            english: "\(measuredIntervalResults.count) comparable completed attempts",
                            norwegian: "\(measuredIntervalResults.count) sammenlignbare fullførte forsøk"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    .padding(16)
                    .athlthPlanCard(radius: 19)
                }
                if exercise.isPersonal {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Only you can see this saved main exercise.",
                            norwegian: "Denne lagrede hovedøvelsen er kun synlig for deg."
                        ),
                        systemImage: "lock"
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
            .padding(16)
        }
        .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
        .navigationTitle(exercise.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.profile.userID) { reloadHistory() }
        .onReceive(NotificationCenter.default.publisher(for: .athlthTrainingDataDidChange)) { _ in
            reloadHistory()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LibraryFavoriteButton(
                    kind: .exercise, itemID: exercise.id,
                    title: exercise.title,
                    subtitle: exercise.category.title + " · " + exercise.detail,
                    icon: "figure.run"
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let onSelect {
                Button {
                    onSelect(exercise.blocksForReuse(in: insertionPhase))
                    dismiss()
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Add main exercise", norwegian: "Legg til hovedøvelse"
                        ),
                        systemImage: "plus"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHPlanDesign.ink)
                .padding(12)
                .background(.regularMaterial)
            }
        }
    }

    private func stepSummary(_ step: WorkoutTemplateBlock) -> String {
        var parts: [String] = []
        if step.isRestOrActiveRecovery {
            parts.append(ATHLTHLocalization.choose(english: "Recovery", norwegian: "Pause"))
        }
        if let duration = step.durationSeconds, duration > 0 {
            let seconds = Int(duration.rounded())
            parts.append(seconds.isMultiple(of: 60)
                ? "\(seconds / 60) min" : "\(seconds) s")
        }
        if let meters = step.distanceMeters, meters > 0 {
            parts.append(meters >= 1_000
                ? String(format: "%.1f km", meters / 1_000)
                : "\(Int(meters.rounded())) m")
        }
        if let repetitions = step.repetitions, repetitions > 1 {
            parts.append("\(repetitions) ×")
        }
        if let zone = step.targetHeartRateZone {
            parts.append("Z\(zone)")
        } else if let source = step.sourceIntensityZoneLabel,
                  !source.isEmpty {
            parts.append(source)
        } else if exercise.familyID == "athlth:running:interval:4x4",
                  step.kind == .run, !step.isRestOrActiveRecovery {
            parts.append(ATHLTHLocalization.isNorwegian ? "S4–S5" : "Z4–Z5")
        }
        return parts.joined(separator: " · ")
    }
}
