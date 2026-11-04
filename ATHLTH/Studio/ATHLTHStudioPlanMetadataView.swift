import SwiftUI

/// A compact, version-aware inspector for editing plan metadata without
/// leaving the iPad canvas. The existing session engine validates conflicts
/// and refuses to discard populated training weeks.
struct ATHLTHStudioPlanMetadataView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    let plan: TrainingPlan
    @State private var title: String
    @State private var summary: String
    @State private var startDate: Date
    @State private var weekCount: Int
    @State private var visibility: ProfileVisibility
    @State private var error: String?

    private let originalVersion: Int
    private let hasPlannedSessions: Bool

    init(plan: TrainingPlan) {
        self.plan = plan
        _title = State(initialValue: plan.title)
        _summary = State(initialValue: plan.summary)
        _startDate = State(initialValue: plan.startDate ?? .now)
        _weekCount = State(initialValue: plan.weeks.count)
        _visibility = State(initialValue: plan.visibility)
        originalVersion = plan.version
        hasPlannedSessions = plan.weeks.contains {
            $0.days.contains { !$0.sessions.isEmpty }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(ATHLTHLocalization.choose(
                    english: "Program", norwegian: "Treningsprogram"
                )) {
                    TextField(ATHLTHLocalization.choose(
                        english: "Name", norwegian: "Navn"
                    ), text: $title)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(ATHLTHLocalization.choose(
                            english: "Description or goal", norwegian: "Beskrivelse eller mål"
                        ))
                        .font(.caption.weight(.semibold))
                        TextEditor(text: $summary)
                            .frame(minHeight: 85)
                    }
                }

                Section(ATHLTHLocalization.choose(
                    english: "Schedule", norwegian: "Tidsplan"
                )) {
                    DatePicker(
                        ATHLTHLocalization.choose(
                            english: "Start date", norwegian: "Startdato"
                        ),
                        selection: $startDate,
                        displayedComponents: .date
                    )
                    .disabled(hasPlannedSessions)

                    if hasPlannedSessions {
                        Text(ATHLTHLocalization.choose(
                            english: "Start date is locked once days contain workouts. This avoids shifting scheduled sessions silently.",
                            norwegian: "Startdatoen låses når dager er fylt ut. Slik unngår vi å flytte planlagte økter uten at du merker det."
                        ))
                        .font(.caption).foregroundStyle(.secondary)
                    }

                    Stepper(value: $weekCount, in: 1...52) {
                        Text("\(weekCount) " + ATHLTHLocalization.choose(
                            english: "weeks", norwegian: "uker"
                        ))
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "Populated weeks can never be discarded by shortening a plan.",
                        norwegian: "Uker med innhold slettes aldri når planen forkortes."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section(ATHLTHLocalization.choose(
                    english: "Sharing", norwegian: "Deling"
                )) {
                    Picker(ATHLTHLocalization.choose(
                        english: "Visibility", norwegian: "Synlighet"
                    ), selection: $visibility) {
                        ForEach(ProfileVisibility.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "This only changes the plan's visibility setting. Your Apple Health recordings are not uploaded by editing a plan.",
                        norwegian: "Dette endrer bare planens synlighet. Apple Health-målinger lastes ikke opp ved redigering."
                    ))
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Plan details", norwegian: "Plandetaljer"
            ))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Save", norwegian: "Lagre"
                    )) {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .frame(minWidth: 330, idealWidth: 450, maxWidth: 520)
        .frame(minHeight: 420, idealHeight: 540, maxHeight: 650)
        .alert(
            ATHLTHLocalization.choose(
                english: "Changes not saved", norwegian: "Endringer ikke lagret"
            ),
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )
        ) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func saveChanges() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120 else {
            error = ATHLTHLocalization.choose(
                english: "Enter a plan name of up to 120 characters.",
                norwegian: "Skriv inn et plannavn på høyst 120 tegn."
            )
            return
        }
        guard session.trainingPlan(withID: plan.id)?.version == originalVersion else {
            error = ATHLTHLocalization.choose(
                english: "The plan changed on another screen. Reopen details to review the latest version.",
                norwegian: "Planen er endret i en annen visning. Åpne plandetaljene på nytt for å se siste versjon."
            )
            return
        }
        let approvedStart = hasPlannedSessions
            ? (plan.startDate ?? startDate)
            : startDate

        guard session.updateTrainingPlan(
            planID: plan.id,
            title: name,
            summary: summary,
            visibility: visibility,
            tags: plan.tags,
            startDate: approvedStart,
            weekCount: weekCount
        ) else {
            error = ATHLTHLocalization.choose(
                english: "The dates overlap another plan, or the shorter program would delete populated weeks. No data was overwritten.",
                norwegian: "Datoene overlapper en annen plan, eller den kortere planen ville slettet uker med innhold. Ingen data ble overskrevet."
            )
            return
        }
        dismiss()
    }
}
