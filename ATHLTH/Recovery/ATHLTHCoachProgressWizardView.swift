import SwiftUI

/// Lets the athlete select the topics/data classes for this single review.
/// The caller must still obtain the existing AI and health-sharing consent.
struct ATHLTHCoachProgressWizardView: View {
    @Environment(\.dismiss) private var dismiss
    let onContinue: (String, ATHLTHCoachProgressScope) -> Void

    private enum Period: Int, CaseIterable, Identifiable {
        case fortnight = 2, month = 4, eightWeeks = 8
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .fortnight: return ATHLTHLocalization.choose(english: "2 weeks", norwegian: "2 uker")
            case .month: return ATHLTHLocalization.choose(english: "4 weeks", norwegian: "4 uker")
            case .eightWeeks: return ATHLTHLocalization.choose(english: "8 weeks", norwegian: "8 uker")
            }
        }
    }

    @State private var selected: Set<ATHLTHCoachProgressScope.Category> = []
    @State private var period: Period = .month
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(tr("Review period", "Periode"), selection: $period) {
                        ForEach(Period.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text(tr("Review", "Analyse"))
                } footer: {
                    Text(tr("The available history may be shorter than your selection.",
                            "Tilgjengelig treningshistorikk kan være kortere enn perioden du velger."))
                }

                Section(tr("Choose data to include", "Velg hvilke data som skal inngå")) {
                    ForEach(ATHLTHCoachProgressScope.Category.allCases) { category in
                        Toggle(category.title, isOn: Binding(
                            get: { selected.contains(category) },
                            set: { enabled in
                                if enabled { selected.insert(category) }
                                else { selected.remove(category) }
                            }
                        ))
                    }
                }

                Section(tr("What should Coach focus on? (optional)", "Hva vil du analysere? (valgfritt)")) {
                    TextField(
                        tr("E.g. running pace, strength or consistency",
                           "F.eks. løpetempo, styrke eller treningsmengde"),
                        text: $notes, axis: .vertical
                    )
                    .lineLimit(2...4)
                }

                Section {
                    Label(tr(
                        "Selecting data does not share it. Coach requests approval for this question before any data leaves your device; unselected categories remain excluded.",
                        "Å velge data deler dem ikke. Coach ber om godkjenning før data sendes for dette spørsmålet; kategorier du ikke velger, utelates."
                    ), systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(tr("Review progress", "Analyser fremgang"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: continueWithCoach) {
                    Label(tr("Review with Coach", "Analyser med Coach"), systemImage: "chart.line.uptrend.xyaxis")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHPlanDesign.accentInk)
                .disabled(selected.isEmpty)
                .padding()
                .background(.regularMaterial)
            }
        }
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private func continueWithCoach() {
        guard !selected.isEmpty else { return }
        let categories = selected.sorted { $0.rawValue < $1.rawValue }
            .map(\.title).joined(separator: ", ")
        let detail = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = tr(
            "Review my progress over the last \(period.rawValue) weeks. Only use these selected categories: \(categories). Do not assume unshared measurements or invent results. Please identify trends, uncertainties and practical next steps.",
            "Analyser treningsfremgangen min de siste \(period.rawValue) ukene. Bruk bare disse valgte kategoriene: \(categories). Ikke gjett på målinger jeg ikke har delt, og ikke finn på resultater. Vis trender, usikkerhet og konkrete råd."
        ) + (detail.isEmpty ? "" : " " + String(detail.prefix(400)))
        onContinue(prompt, ATHLTHCoachProgressScope(
            selected: selected, windowDays: period.rawValue * 7
        ))
    }
}
