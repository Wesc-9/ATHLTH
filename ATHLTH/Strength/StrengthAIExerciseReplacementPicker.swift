import SwiftUI

/// Replaces one suggested exercise without generating a new program.
/// The caller supplies the same pre-approved library candidate list that
/// is permitted to reach the AI service.
struct StrengthAIExerciseReplacementPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ExerciseLibraryStore
    @State private var searchText = ""

    let choices: [ExerciseLibraryEntry]
    let onPick: (ExerciseLibraryEntry) -> Void

    private var filtered: [ExerciseLibraryEntry] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return choices }
        return choices.filter {
            $0.canonicalName.localizedCaseInsensitiveContains(searchText) ||
                $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No matching library exercises",
                            norwegian: "Ingen passende øvelser i biblioteket"
                        ),
                        systemImage: "dumbbell",
                        description: Text(ATHLTHLocalization.choose(
                            english: "Try another search or adjust your generation filters.",
                            norwegian: "Prøv et annet søk eller juster valgene for økten."
                        ))
                    )
                } else {
                    List(filtered) { entry in
                        Button {
                            onPick(entry)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "dumbbell")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 38, height: 38)
                                    .background(.quaternary.opacity(0.4),
                                                in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(library.localizedExerciseName(entry))
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(entry.source == .custom
                                        ? ATHLTHLocalization.choose(
                                            english: "My exercise",
                                            norwegian: "Min øvelse"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english: "ATHLTH library",
                                            norwegian: "ATHLTH-biblioteket"
                                        ))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Replace exercise",
                norwegian: "Bytt øvelse"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: ATHLTHLocalization.choose(
                english: "Search eligible exercises",
                norwegian: "Søk i tilgjengelige øvelser"
            ))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
