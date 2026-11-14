import SwiftUI

/// Compact grid footer: actual main-part exercises first, then a short
/// overflow count. Existing list cards can keep their full expandable recipe.
struct ATHLTHWorkoutGridDetails: View {
    let workout: PlannedSession?
    let catalogBlocks: [WorkoutTemplateBlock]?
    var estimatedMinutes: Int?

    init(workout: PlannedSession, estimatedMinutes: Int? = nil) {
        self.workout = workout
        self.catalogBlocks = nil
        self.estimatedMinutes = estimatedMinutes
    }

    init(entry: WorkoutTemplateCatalogEntry) {
        self.workout = nil
        self.catalogBlocks = entry.blocks
        self.estimatedMinutes = entry.estimatedDurationMinutes
    }

    private var preview: (titles: [String], remaining: Int) {
        if let catalogBlocks {
            return ATHLTHWorkoutLibraryExerciseIndex.preview(blocks: catalogBlocks)
        }
        if let workout {
            return ATHLTHWorkoutLibraryExerciseIndex.preview(for: workout)
        }
        return ([], 0)
    }

    private var durationMinutes: Int? {
        if let estimatedMinutes { return estimatedMinutes }
        if let workout {
            return workout.durationMinutes ??
                ATHLTHWorkoutDurationEstimator.previewMinutes(
                    for: ATHLTHUnifiedWorkout.editorBlocks(from: workout)
                )
        }
        if let catalogBlocks {
            return ATHLTHWorkoutDurationEstimator.previewMinutes(for: catalogBlocks)
        }
        return nil
    }

    var body: some View {
        let summary = preview
        VStack(alignment: .leading, spacing: 4) {
            ForEach(summary.titles, id: \.self) { title in
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .lineLimit(1)
            }
            if summary.remaining > 0 {
                Text(ATHLTHLocalization.choose(
                    english: "+ \(summary.remaining) more",
                    norwegian: "+ \(summary.remaining) flere"
                ))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            }
            if let minutes = durationMinutes, minutes > 0 {
                Label("~\(minutes) min", systemImage: "clock")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The workout exercise filter must select a real movement, not arbitrary
/// keyword matches against marketing descriptions or muscle groups.
struct ATHLTHWorkoutExerciseFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedExercise: String?
    let exerciseNames: [String]
    @State private var query = ""

    private var visibleExercises: [String] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return exerciseNames
        }
        return exerciseNames.filter {
            $0.localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedExercise = nil
                    dismiss()
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "All exercises", norwegian: "Alle øvelser"
                        ),
                        systemImage: selectedExercise == nil
                            ? "checkmark.circle.fill" : "square.grid.2x2"
                    )
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                }

                ForEach(visibleExercises, id: \.self) { name in
                    Button {
                        selectedExercise = name
                        dismiss()
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: "dumbbell")
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            Text(name)
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            Spacer(minLength: 2)
                            if ATHLTHWorkoutLibraryExerciseIndex.normalize(
                                selectedExercise ?? ""
                            ) == ATHLTHWorkoutLibraryExerciseIndex.normalize(name) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            }
                        }
                        .frame(minHeight: 43)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHPlanDesign.warmCanvas)
            .searchable(
                text: $query,
                prompt: ATHLTHLocalization.choose(
                    english: "Search exercises in workouts",
                    norwegian: "Søk etter øvelse i treningsøkter"
                )
            )
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Find workouts by exercise",
                norwegian: "Finn økter med en øvelse"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close", norwegian: "Lukk"
                    )) { dismiss() }
                }
            }
            .overlay {
                if visibleExercises.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}
