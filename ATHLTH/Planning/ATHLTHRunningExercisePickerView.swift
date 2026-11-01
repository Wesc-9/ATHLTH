import SwiftUI

/// Used only when adding exercises to a running session. Intentionally does
/// not contain strength, cycling, equipment scanning or general exercise data.
struct ATHLTHRunningExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let userID: UUID
    let phase: WorkoutPhaseKind
    let onSelect: ([WorkoutTemplateBlock]) -> Void

    @State private var selectedTab = 0
    @State private var savedSets: [ATHLTHRunningMainSet] = []

    var body: some View {
        VStack(spacing: 0) {
            Picker(ATHLTHLocalization.choose(
                english: "Running library", norwegian: "Løpebibliotek"
            ), selection: $selectedTab) {
                Text(ATHLTHLocalization.choose(
                    english: "Running exercises", norwegian: "Løpeøvelser"
                )).tag(0)
                Text(ATHLTHLocalization.choose(
                    english: "My main sets", norwegian: "Mine hoveddeler"
                )).tag(1)
            }
            .pickerStyle(.segmented)
            .padding(16)

            if selectedTab == 1 && savedSets.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(
                        english: "No saved main sets", norwegian: "Ingen lagrede hoveddeler"
                    ),
                    systemImage: "bookmark",
                    description: Text(ATHLTHLocalization.choose(
                        english: "Save the main section of an advanced running workout to reuse it.",
                        norwegian: "Lagre hoveddelen i en avansert løpeøkt for å bruke den igjen."
                    ))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if selectedTab == 0 {
                            ForEach(ATHLTHRunningExercisePreset.allCases) { preset in
                                selectionRow(
                                    title: preset.title,
                                    detail: preset.detail,
                                    symbol: "figure.run"
                                ) {
                                    onSelect(preset.blocks(in: phase))
                                    dismiss()
                                }
                            }
                        } else {
                            ForEach(savedSets) { set in
                                selectionRow(
                                    title: set.title,
                                    detail: ATHLTHLocalization.choose(
                                        english: "\(set.blocks.count) saved steps",
                                        norwegian: "\(set.blocks.count) lagrede deløkter"
                                    ),
                                    symbol: "bookmark.fill"
                                ) {
                                    onSelect(set.inserting())
                                    dismiss()
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        ATHLTHRunningMainSet.delete(
                                            id: set.id, userID: userID
                                        )
                                        savedSets = ATHLTHRunningMainSet.load(userID: userID)
                                    } label: {
                                        Label(ATHLTHLocalization.choose(
                                            english: "Delete", norwegian: "Slett"
                                        ), systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Add running exercise", norwegian: "Legg til løpeøvelse"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(ATHLTHLocalization.choose(english: "Close", norwegian: "Lukk")) {
                    dismiss()
                }
            }
        }
        .onAppear { savedSets = ATHLTHRunningMainSet.load(userID: userID) }
    }

    private func selectionRow(
        title: String, detail: String, symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(ATHLTHPlanDesign.accent)
                    .frame(width: 48, height: 48)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(ATHLTHPlanDesign.accent)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .athlthPlanCard(radius: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + ". " + detail)
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Add to planned running workout",
            norwegian: "Legg til i den planlagte løpeøkten"
        ))
    }
}
