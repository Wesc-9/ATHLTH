import SwiftUI

/// One browser for full main-section exercises: public curated prescriptions
/// and private sections captured from the athlete's own saved workouts.
struct ATHLTHCompoundExerciseLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @ObservedObject private var catalog = WorkoutTemplateCatalogStore.shared

    var runningOnly = false
    var insertionPhase: WorkoutPhaseKind = .main
    var onSelect: (([WorkoutTemplateBlock]) -> Void)? = nil

    @State private var records: [ATHLTHCompoundExercise] = []
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
        // Build once on source revisions rather than hashing every exercise
        // on each search keystroke and SwiftUI view publication.
        records = ATHLTHCompoundExerciseCatalog.build(
            running: RunningWorkoutLibraryStore.builtInTemplates,
            workoutCatalog: catalog.entries,
            saved: mySections
        )
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

    private var fourByFourResults: [ATHLTHFourByFourRecords.Result] {
        guard exercise.familyID == "athlth:running:interval:4x4",
              let recovery = ATHLTHCompoundExerciseCatalog.fourByFourRecovery(
                exercise.blocks
              )
        else { return [] }
        return ATHLTHFourByFourRecords.records(
            ATHLTHRunningPerformanceHistory.load(userID: session.profile.userID)
        ).filter { $0.recoverySeconds == recovery }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(exercise.category.title.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    Text(exercise.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(exercise.detail)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }

                VStack(alignment: .leading, spacing: 13) {
                    Text(ATHLTHLocalization.choose(
                        english: "Main section", norwegian: "Hoveddel"
                    ))
                    .font(.headline.weight(.semibold))
                    ForEach(Array(exercise.blocks.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .frame(width: 25)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.title)
                                    .font(.subheadline.weight(.medium))
                                Text(stepSummary(step))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
                .athlthPlanCard(radius: 19)

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
        }
        return parts.joined(separator: " · ")
    }
}
