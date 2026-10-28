import SwiftUI

/// A deliberate review step for Coach workout creation. Private training
/// notes are copied, never live-bound. Injury text is excluded by default.
struct ATHLTHCoachWorkoutRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onContinue: (String, Bool) -> Void

    @State private var workoutRequest: String
    @State private var trainingNotes: String
    @State private var injuryNotes: String
    @State private var includeInjuryDetails = false

    init(
        request: String,
        profile: ATHLTHTrainingProfile,
        onContinue: @escaping (String, Bool) -> Void
    ) {
        self.onContinue = onContinue
        _workoutRequest = State(initialValue: request)
        _trainingNotes = State(initialValue: profile.trainingNotes)
        _injuryNotes = State(initialValue: profile.injuryAndLimitations)
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(tr("WORKOUT WITH COACH", "ØKT MED COACH"),
                          systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)

                    Text(tr("Your context, your choice",
                            "Din profil – du bestemmer"))
                        .font(.system(size: 25, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)

                    Text(tr(
                        "Review the saved information Coach should use for this workout. You can edit or remove anything below without changing your Training Profile.",
                        "Gjennomgå det Coach skal bruke for denne økten. Du kan endre eller fjerne alt nedenfor uten å endre den lagrede treningsprofilen."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                    section(tr("What do you want to train?", "Hva vil du trene?"),
                            text: $workoutRequest, canClear: false)

                    section(tr("From your Training Profile", "Fra treningsprofilen"),
                            text: $trainingNotes, canClear: true)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(tr("Injuries and limitations",
                                     "Skader og begrensninger"),
                                  systemImage: "lock.shield")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if !injuryNotes.isEmpty {
                                Button(tr("Clear", "Fjern")) { injuryNotes = "" }
                                    .font(.caption)
                            }
                        }
                        TextEditor(text: $injuryNotes)
                            .frame(minHeight: 78)
                            .scrollContentBackground(.hidden)
                            .padding(7)
                            .background(ATHLTHPlanDesign.selectedSurface,
                                        in: RoundedRectangle(cornerRadius: 13))

                        Toggle(isOn: $includeInjuryDetails) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tr("Include injury notes in this request",
                                        "Inkluder skadeopplysninger i denne forespørselen"))
                                    .font(.subheadline.weight(.semibold))
                                Text(tr(
                                    "Off by default. Choosing this will also require the separate AI health-sharing confirmation before the request is sent.",
                                    "Av som standard. Du må også godkjenne deling av helsedata før forespørselen sendes."
                                ))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                        }
                        .tint(ATHLTHPlanDesign.accentInk)
                    }
                    .padding(14)
                    .athlthPlanCard(radius: 17)

                    Button {
                        let base = String(workoutRequest.trimmingCharacters(
                            in: .whitespacesAndNewlines).prefix(1_100))
                        let background = trainingNotes.trimmingCharacters(
                            in: .whitespacesAndNewlines)
                        let limitations = injuryNotes.trimmingCharacters(
                            in: .whitespacesAndNewlines)
                        var full = base + "\n\nCreate a structured workout for review in ATHLTH. Never invent my working weights or goal pace."
                        if !background.isEmpty {
                            full += "\nAthlete's reviewed training background: " +
                                String(background.prefix(700))
                        }
                        if includeInjuryDetails && !limitations.isEmpty {
                            full += "\nExplicitly reviewed injury/limitation notes: " +
                                String(limitations.prefix(800)) +
                                "\nAvoid movements the athlete describes as unsuitable. Ask for clarification if a safe substitution is unclear."
                        }
                        dismiss()
                        onContinue(full, includeInjuryDetails && !limitations.isEmpty)
                    } label: {
                        Label(tr("Continue to Coach", "Fortsett til Coach"),
                              systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHPlanDesign.accentInk)
                    .disabled(workoutRequest.trimmingCharacters(
                        in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Create workout", "Lag treningsøkt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, text: Binding<String>,
                         canClear: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if canClear && !text.wrappedValue.isEmpty {
                    Button(tr("Clear", "Fjern")) { text.wrappedValue = "" }
                        .font(.caption)
                }
            }
            TextEditor(text: text)
                .frame(minHeight: 75)
                .scrollContentBackground(.hidden)
                .padding(7)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 13))
        }
        .padding(14)
        .athlthPlanCard(radius: 17)
    }
}
