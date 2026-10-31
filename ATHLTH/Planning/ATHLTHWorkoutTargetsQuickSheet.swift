import SwiftUI

/// Edits the real structured recipe. Never creates a ghost step or modifies
/// a workout until the user explicitly changes a target in its existing row.
struct ATHLTHWorkoutTargetsQuickSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var blocks: [WorkoutTemplateBlock]

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        NavigationStack {
            Group {
                if blocks.isEmpty {
                    ContentUnavailableView(
                        tr("Add a step first", "Legg til en deløkt først"),
                        systemImage: "heart.text.square",
                        description: Text(tr(
                            "Then select it here to set a heart rate zone, effort or target pace.",
                            "Velg deløkten her etterpå for å angi pulssone, anstrengelse eller måltempo."
                        ))
                    )
                } else {
                    List {
                        Section {
                            ForEach(blocks.indices, id: \.self) { index in
                                NavigationLink {
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 16) {
                                            ATHLTHPlannedIntensityEditor(
                                                block: $blocks[index]
                                            )
                                            if blocks[index].kind == .run {
                                                ATHLTHPlannedRunStepEditor(
                                                    block: $blocks[index]
                                                )
                                            }
                                        }
                                        .padding(16)
                                    }
                                    .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
                                    .navigationTitle(
                                        ATHLTHWorkoutNameSuggestion.displayStepTitle(
                                            blocks[index]
                                        )
                                    )
                                    .navigationBarTitleDisplayMode(.inline)
                                } label: {
                                    Label(
                                        ATHLTHWorkoutNameSuggestion.displayStepTitle(
                                            blocks[index]
                                        ),
                                        systemImage: blocks[index].kind.systemImage
                                    )
                                }
                            }
                        } header: {
                            Text(tr("Choose workout step", "Velg deløkt"))
                        } footer: {
                            Text(tr(
                                "These are planned targets, not live measurements or sensor pairing.",
                                "Dette er planlagte mål, ikke målt puls eller tilkobling av pulsmåler."
                            ))
                        }
                    }
                }
            }
            .navigationTitle(tr("Heart rate and pace", "Puls og tempo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) { dismiss() }
                }
            }
        }
    }
}
